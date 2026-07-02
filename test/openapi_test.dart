import 'dart:convert';
import 'dart:io';

import 'package:dart_server/dart_server.dart';
import 'package:test/test.dart';

class DocsController extends Controller {
  @override
  String get basePath => '/books';

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', index,
        doc: ApiDoc(
          summary: 'List books',
          tags: ['catalog'],
          params: {
            'page': ApiParam(
                description: 'Page number', schema: ApiSchema.integer()),
          },
          responses: {
            200: ApiResponse('A page of books',
                schema: ApiSchema.array(ApiSchema.object(
                  properties: {'title': ApiSchema.string()},
                ))),
          },
        ));
    routes.get('/:id', show,
        doc: ApiDoc(
          summary: 'Fetch one book',
          params: {'id': ApiParam(description: 'Book id')},
          responses: {
            200: ApiResponse('The book'),
            404: ApiResponse('Not found'),
          },
        ));
    routes.post('/', store,
        doc: ApiDoc(
          summary: 'Create a book',
          body: ApiBody(
            schema: ApiSchema.object(
              properties: {'title': ApiSchema.string()},
              required: ['title'],
            ),
          ),
          security: ['bearer'],
          responses: {201: ApiResponse('Created')},
        ));
    routes.get('/secret', secret, doc: ApiDoc(hidden: true));
  }

  Response index(Request req) => Response.json([]);
  Response show(Request req) => Response.json({});
  Response store(Request req) => Response.status(201);
  Response secret(Request req) => Response.text('shh');
}

void main() {
  group('OpenApiGenerator', () {
    Map<String, dynamic> gen(List<DocumentedRoute> routes) =>
        OpenApiGenerator.generate(
            routes: routes, title: 'Test API', version: '2.0.0');

    test('converts :params and wildcards to OpenAPI syntax', () {
      final spec = gen([
        (method: 'GET', pattern: '/users/:id/posts/:postId', doc: null),
        (method: 'GET', pattern: '/files/*', doc: null),
      ]);
      final paths = spec['paths'] as Map<String, dynamic>;
      expect(paths.keys, contains('/users/{id}/posts/{postId}'));
      expect(paths.keys, contains('/files/{path}'));

      final op = paths['/users/{id}/posts/{postId}']['get'];
      final names =
          (op['parameters'] as List).map((p) => (p as Map)['name']).toList();
      expect(names, ['id', 'postId']);
      expect((op['parameters'] as List).first['required'], isTrue);
    });

    test('defaults: tag from first segment, bare 200 response', () {
      final spec = gen([(method: 'GET', pattern: '/users', doc: null)]);
      final op = spec['paths']['/users']['get'] as Map<String, dynamic>;
      expect(op['tags'], ['users']);
      expect(op['responses'], {
        '200': {'description': 'Success'},
      });
    });

    test('skips ALL-method routes, hidden routes and excluded prefixes', () {
      final spec = OpenApiGenerator.generate(
        routes: [
          (method: 'ALL', pattern: '/anything', doc: null),
          (method: 'GET', pattern: '/hidden', doc: ApiDoc(hidden: true)),
          (method: 'GET', pattern: '/docs', doc: null),
          (method: 'GET', pattern: '/docs/openapi.json', doc: null),
          (method: 'GET', pattern: '/visible', doc: null),
        ],
        title: 't',
        version: '1',
        excludePaths: ['/docs'],
      );
      expect((spec['paths'] as Map).keys, ['/visible']);
    });

    test('same-hierarchy paths with different param names merge into one', () {
      final spec = gen([
        (method: 'GET', pattern: '/users/:id', doc: null),
        (method: 'PUT', pattern: '/users/:userId', doc: null),
      ]);
      final paths = spec['paths'] as Map<String, dynamic>;
      // One path item, keyed by the first-seen template.
      expect(paths.keys, ['/users/{id}']);
      expect(paths['/users/{id}'].keys, containsAll(['get', 'put']));
      // The later operation's parameter is renamed to the canonical name.
      final putParams = paths['/users/{id}']['put']['parameters'] as List;
      expect(putParams.single['name'], 'id');
    });

    test('duplicate method+path keeps the first registration (router wins)',
        () {
      final spec = gen([
        (method: 'GET', pattern: '/users', doc: ApiDoc(summary: 'served')),
        (method: 'GET', pattern: '/users', doc: ApiDoc(summary: 'shadowed')),
      ]);
      expect(spec['paths']['/users']['get']['summary'], 'served');
    });

    test('a wildcard next to a :path param gets a non-colliding name', () {
      final spec = gen([(method: 'GET', pattern: '/files/:path/*', doc: null)]);
      final paths = spec['paths'] as Map<String, dynamic>;
      expect(paths.keys, ['/files/{path}/{path2}']);
      final names = (paths.values.single['get']['parameters'] as List)
          .map((p) => (p as Map)['name'])
          .toList();
      expect(names, ['path', 'path2']);
    });

    test('info, servers and securitySchemes land in the document', () {
      final spec = OpenApiGenerator.generate(
        routes: const [],
        title: 'My API',
        version: '3.1.4',
        description: 'desc',
        servers: ['https://api.example.com'],
        securitySchemes: {
          'bearer': ApiSecurityScheme.bearer(),
        },
      );
      expect(spec['openapi'], '3.0.3');
      expect(spec['info'],
          {'title': 'My API', 'version': '3.1.4', 'description': 'desc'});
      expect(spec['servers'], [
        {'url': 'https://api.example.com'},
      ]);
      expect(
          spec['components']['securitySchemes']['bearer']['scheme'], 'bearer');
    });

    test('ApiSecurityScheme factories produce the right OpenAPI shapes', () {
      expect(
        ApiSecurityScheme.apiKey('x-api-key', description: 'demo').toJson(),
        {
          'type': 'apiKey',
          'name': 'x-api-key',
          'in': 'header',
          'description': 'demo',
        },
      );
      expect(ApiSecurityScheme.bearer(bearerFormat: 'JWT').toJson(),
          {'type': 'http', 'scheme': 'bearer', 'bearerFormat': 'JWT'});
      expect(ApiSecurityScheme.basic().toJson(),
          {'type': 'http', 'scheme': 'basic'});
      expect(ApiSecurityScheme.raw({'type': 'openIdConnect'}).toJson(),
          {'type': 'openIdConnect'});
    });
  });

  group('useOpenApi end-to-end', () {
    late DartServer app;
    late HttpServer server;
    late HttpClient client;

    setUp(() => client = HttpClient());

    tearDown(() async {
      client.close(force: true);
      await app.close(force: true);
    });

    Future<({int status, String body, String? contentType})> get(
        String path) async {
      final uri =
          Uri.parse('http://${server.address.host}:${server.port}$path');
      final response = await (await client.getUrl(uri)).close();
      return (
        status: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
        contentType: response.headers.contentType?.mimeType,
      );
    }

    test('serves the UI page and the generated specification', () async {
      app = await DartServerFactory.create(
          Module(controllers: [(i) => DocsController()]));
      app.useOpenApi(
        title: 'Books API',
        version: '1.2.3',
        securitySchemes: {
          'bearer': ApiSecurityScheme.bearer(),
        },
      );
      server = await app.listen(0,
          address: InternetAddress.loopbackIPv4, quiet: true);

      final ui = await get('/docs');
      expect(ui.status, 200);
      expect(ui.contentType, 'text/html');
      expect(ui.body, contains('swagger-ui'));
      expect(ui.body, contains('/docs/openapi.json'));

      final res = await get('/docs/openapi.json');
      expect(res.status, 200);
      expect(res.contentType, 'application/json');
      final spec = jsonDecode(res.body) as Map<String, dynamic>;
      expect(spec['info']['title'], 'Books API');

      final paths = spec['paths'] as Map<String, dynamic>;
      // Controller routes present, enriched.
      expect(paths['/books']['get']['summary'], 'List books');
      expect(paths['/books']['get']['tags'], ['catalog']);
      expect(paths['/books/{id}']['get']['responses'].keys,
          containsAll(['200', '404']));
      expect(
          paths['/books']['post']['requestBody']['content']['application/json']
              ['schema']['required'],
          ['title']);
      expect(paths['/books']['post']['security'], [
        {'bearer': <String>[]},
      ]);
      // Query param docs become query parameters.
      final listParams = paths['/books']['get']['parameters'] as List;
      expect(listParams.single['in'], 'query');
      expect(listParams.single['name'], 'page');
      // Hidden route and the docs endpoints themselves are absent.
      expect(paths.keys, isNot(contains('/books/secret')));
      expect(paths.keys, isNot(contains('/docs')));
      expect(paths.keys, isNot(contains('/docs/openapi.json')));
    });

    test('documents Express-style routes registered with doc:', () async {
      app = DartServer();
      app.get('/ping', (req) => Response.text('pong'),
          doc: ApiDoc(summary: 'Health ping'));
      app.useOpenApi();
      server = await app.listen(0,
          address: InternetAddress.loopbackIPv4, quiet: true);

      final spec = jsonDecode((await get('/docs/openapi.json')).body) as Map;
      expect(spec['paths']['/ping']['get']['summary'], 'Health ping');
    });

    test('a custom dev-dashboard path is excluded from the spec', () async {
      app = DartServer();
      app.get('/api/thing', (req) => Response.text('x'));
      app.useDevTools(path: '/admin/dev', enabled: true);
      app.useOpenApi();
      server = await app.listen(0,
          address: InternetAddress.loopbackIPv4, quiet: true);

      final spec = jsonDecode((await get('/docs/openapi.json')).body) as Map;
      final paths = (spec['paths'] as Map).keys.toList();
      expect(paths, contains('/api/thing'));
      expect(
          paths.where((p) => p.toString().startsWith('/admin/dev')), isEmpty);
    });

    test('enabled: false mounts nothing', () async {
      app = DartServer();
      app.get('/x', (req) => Response.text('x'));
      expect(app.useOpenApi(enabled: false), isFalse);
      server = await app.listen(0,
          address: InternetAddress.loopbackIPv4, quiet: true);
      expect((await get('/docs')).status, 404);
    });
  });
}
