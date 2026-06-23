import 'dart:convert';
import 'dart:io';

import 'package:dart_server/dart_server.dart';
import 'package:test/test.dart';

void main() {
  late DartServer app;
  late HttpServer server;
  late HttpClient client;

  /// Issues a request and decodes the body.
  Future<({int status, String body, HttpHeaders headers})> send(
    String method,
    String path, {
    Object? json,
    String? rawBody,
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse('http://${server.address.host}:${server.port}$path');
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (json != null) {
      request.headers.contentType = ContentType('application', 'json');
      request.write(jsonEncode(json));
    } else if (rawBody != null) {
      request.write(rawBody);
    }
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: body, headers: response.headers);
  }

  setUp(() async {
    app = DartServer();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await app.close(force: true);
  });

  /// Binds the app to an ephemeral loopback port for the test.
  Future<void> start() async {
    server = await app.listen(0, address: InternetAddress.loopbackIPv4,
        quiet: true);
  }

  group('routing', () {
    test('GET / returns plain text', () async {
      app.get('/', (req) => Response.text('Hello World'));
      await start();

      final res = await send('GET', '/');
      expect(res.status, 200);
      expect(res.body, 'Hello World');
      expect(res.headers.contentType?.mimeType, 'text/plain');
    });

    test('route params are parsed into req.params', () async {
      app.get('/users/:id', (req) => Response.json({'id': req.params['id']}));
      await start();

      final res = await send('GET', '/users/42');
      expect(jsonDecode(res.body), {'id': '42'});
    });

    test('query string is parsed into req.query', () async {
      app.get('/search', (req) => Response.json({'q': req.query['q']}));
      await start();

      expect(jsonDecode((await send('GET', '/search?q=dart')).body), {'q': 'dart'});
    });

    test('trailing wildcard captures the remainder into params["*"]', () async {
      app.get('/files/*', (req) => Response.json({'rest': req.params['*']}));
      await start();

      final res = await send('GET', '/files/a/b/c.txt');
      expect(jsonDecode(res.body), {'rest': 'a/b/c.txt'});
    });

    test('a non-trailing wildcard is rejected at registration', () {
      expect(() => app.get('/files/*/download', (req) => Response.text('x')),
          throwsArgumentError);
    });

    test('unknown route returns 404 JSON', () async {
      await start();
      final res = await send('GET', '/nope');
      expect(res.status, 404);
      expect(jsonDecode(res.body)['error'], 'Not Found');
    });

    test('known path with wrong method returns 405 + Allow header', () async {
      app.get('/users', (req) => Response.text('list'));
      await start();

      final res = await send('POST', '/users');
      expect(res.status, 405);
      expect(res.headers.value('allow'), contains('GET'));
    });

    test('malformed percent-encoding in a param yields a match, not a 500',
        () async {
      app.get('/users/:id', (req) => Response.json({'id': req.params['id']}));
      await start();

      // %E0%A4 is a valid escape that decodes to invalid UTF-8.
      final res = await send('GET', '/users/%E0%A4');
      expect(res.status, 200);
    });
  });

  group('body parsing', () {
    test('POST body is parsed via req.json()', () async {
      app.post('/login', (req) async {
        final body = await req.json() as Map<String, dynamic>;
        return Response.json({'email': body['email']});
      });
      await start();

      final res = await send('POST', '/login', json: {'email': 'a@b.com'});
      expect(jsonDecode(res.body), {'email': 'a@b.com'});
    });

    test('malformed JSON body surfaces as a 500', () async {
      app.post('/x', (req) async => Response.json(await req.json()));
      await start();

      final res = await send('POST', '/x', rawBody: '{not json');
      expect(res.status, 500);
    });

    test('json() re-throws on every call for a malformed body', () async {
      app.post('/double', (req) async {
        var first = false, second = false;
        try {
          await req.json();
        } catch (_) {
          first = true;
        }
        try {
          await req.json();
        } catch (_) {
          second = true;
        }
        return Response.json({'first': first, 'second': second});
      });
      await start();

      final res = await send('POST', '/double', rawBody: '{bad');
      expect(jsonDecode(res.body), {'first': true, 'second': true});
    });

    test('request body larger than maxBodyBytes is rejected with 413', () async {
      app = DartServer(maxBodyBytes: 16);
      app.post('/upload', (req) => Response.text('ok'));
      await start();

      final res = await send('POST', '/upload', rawBody: 'x' * 1000);
      expect(res.status, 413);
    });
  });

  group('middleware', () {
    test('runs in order and can short-circuit', () async {
      final order = <String>[];
      app.use((req, next) async {
        order.add('a-before');
        final res = await next();
        order.add('a-after');
        return res;
      });
      app.use((req, next) async {
        if (req.headers['x-block'] == 'yes') {
          return Response.status(401, {'error': 'blocked'});
        }
        return next();
      });
      app.get('/', (req) {
        order.add('handler');
        return Response.text('ok');
      });
      await start();

      final ok = await send('GET', '/');
      expect(ok.status, 200);
      expect(order, ['a-before', 'handler', 'a-after']);

      final blocked = await send('GET', '/', headers: {'x-block': 'yes'});
      expect(blocked.status, 401);
    });

    test('a handler error still flows back through middleware', () async {
      Response? observed;
      app.use((req, next) async {
        observed = await next();
        return observed!;
      });
      app.get('/boom', (req) => throw HttpError.notFound('gone'));
      await start();

      final res = await send('GET', '/boom');
      expect(res.status, 404);
      expect(observed?.statusCode, 404, reason: 'middleware sees error response');
    });
  });

  group('errors', () {
    test('thrown HttpError maps to its status code', () async {
      app.get('/missing', (req) => throw HttpError.notFound('gone'));
      await start();

      final res = await send('GET', '/missing');
      expect(res.status, 404);
      expect(jsonDecode(res.body), containsPair('error', 'gone'));
    });

    test('uncaught error returns 500 JSON', () async {
      app.get('/boom', (req) => throw StateError('kaboom'));
      await start();

      final res = await send('GET', '/boom');
      expect(res.status, 500);
      expect(jsonDecode(res.body)['statusCode'], 500);
    });
  });

  group('HEAD & bodiless responses', () {
    test('HEAD falls back to the GET handler with no body but a length',
        () async {
      app.get('/', (req) => Response.text('Hello World'));
      await start();

      final res = await send('HEAD', '/');
      expect(res.status, 200);
      expect(res.body, isEmpty);
      expect(res.headers.value('content-length'), '11');
    });

    test('Response.status(204) sends no body', () async {
      app.delete('/users/:id', (req) => Response.status(204));
      await start();

      final res = await send('DELETE', '/users/1');
      expect(res.status, 204);
      expect(res.body, isEmpty);
      // dart:io may auto-send `content-length: 0`; what matters is no body and
      // never a non-zero length.
      expect(res.headers.value('content-length'), anyOf(isNull, '0'));
    });

    test('304 responses carry no body even with data', () async {
      app.get('/cached', (req) => Response.status(304, {'ignored': true}));
      await start();

      final res = await send('GET', '/cached');
      expect(res.status, 304);
      expect(res.body, isEmpty);
    });
  });

  group('cors', () {
    test('credentials:true with a wildcard origin throws', () {
      expect(() => cors(credentials: true), throwsArgumentError);
    });

    test('answers a real preflight and adds headers to actual requests',
        () async {
      app.use(cors(origin: 'https://example.com'));
      app.get('/', (req) => Response.text('ok'));
      await start();

      final preflight = await send('OPTIONS', '/',
          headers: {'Access-Control-Request-Method': 'GET'});
      expect(preflight.status, 204);
      expect(preflight.headers.value('access-control-allow-origin'),
          'https://example.com');

      final actual = await send('GET', '/');
      expect(actual.headers.value('access-control-allow-origin'),
          'https://example.com');
    });

    test('an allow-list reflects only member origins', () async {
      app.use(cors(origins: ['https://a.com'], credentials: true));
      app.get('/', (req) => Response.text('ok'));
      await start();

      final allowed =
          await send('GET', '/', headers: {'Origin': 'https://a.com'});
      expect(allowed.headers.value('access-control-allow-origin'),
          'https://a.com');

      final denied =
          await send('GET', '/', headers: {'Origin': 'https://evil.com'});
      expect(denied.headers.value('access-control-allow-origin'), isNull);
    });

    test('cors headers are present on error responses too', () async {
      app.use(cors());
      app.get('/boom', (req) => throw StateError('x'));
      await start();

      final res = await send('GET', '/boom');
      expect(res.status, 500);
      expect(res.headers.value('access-control-allow-origin'), '*');
    });

    test('does not shadow an explicit OPTIONS route', () async {
      app.use(cors());
      app.options('/thing', (req) => Response.json({'custom': true}));
      await start();

      // No Access-Control-Request-Method header => not a preflight.
      final res = await send('OPTIONS', '/thing');
      expect(jsonDecode(res.body), {'custom': true});
    });
  });

  group('logger', () {
    test('logs successful and errored requests', () async {
      final lines = <String>[];
      app.use(logger(log: lines.add));
      app.get('/ok', (req) => Response.text('ok'));
      app.get('/boom', (req) => throw StateError('x'));
      await start();

      await send('GET', '/ok');
      await send('GET', '/boom');

      expect(lines.any((l) => l.contains('GET /ok 200')), isTrue);
      expect(lines.any((l) => l.contains('GET /boom 500')), isTrue);
    });
  });

  group('serveStatic', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('dart_server_static');
      await File('${dir.path}/index.html').writeAsString('<h1>home</h1>');
      await File('${dir.path}/data.json').writeAsString('{"a":1}');
    });

    tearDown(() async => dir.delete(recursive: true));

    test('serves a file with the right content type', () async {
      app.use(serveStatic(dir.path));
      await start();

      final res = await send('GET', '/data.json');
      expect(res.status, 200);
      expect(jsonDecode(res.body), {'a': 1});
      expect(res.headers.contentType?.mimeType, 'application/json');
    });

    test('serves index.html for the directory root', () async {
      app.use(serveStatic(dir.path));
      await start();

      final res = await send('GET', '/');
      expect(res.body, contains('home'));
    });

    test('falls through to routes on a miss', () async {
      app.use(serveStatic(dir.path));
      app.get('/api', (req) => Response.text('route'));
      await start();

      expect((await send('GET', '/api')).body, 'route');
      expect((await send('GET', '/missing.txt')).status, 404);
    });

    test('does not serve a file outside the root via `..` traversal', () async {
      // A secret sibling of the served root.
      final secret = File('${dir.parent.path}/dart_server_secret.txt');
      await secret.writeAsString('TOP SECRET');
      addTearDown(() async => secret.delete());

      app.use(serveStatic(dir.path));
      await start();

      final res = await send('GET', '/../dart_server_secret.txt');
      expect(res.status, isNot(200));
      expect(res.body, isNot(contains('TOP SECRET')));
    });

    test('rejects a symlink that escapes the root with 403', () async {
      final secret = File('${dir.parent.path}/dart_server_secret2.txt');
      await secret.writeAsString('TOP SECRET');
      addTearDown(() async => secret.delete());
      await Link('${dir.path}/leak.txt').create(secret.path);

      app.use(serveStatic(dir.path));
      await start();

      final res = await send('GET', '/leak.txt');
      expect(res.status, 403);
      expect(res.body, isNot(contains('TOP SECRET')));
    });
  });

  group('dev tools', () {
    test('disabled => dashboard 404s and nothing is recorded', () async {
      app.useDevTools(enabled: false);
      app.get('/x', (req) => Response.text('x'));
      await start();

      expect(app.devTools, isNull);
      await send('GET', '/x');
      expect((await send('GET', '/__dev')).status, 404);
    });

    test('enabled => serves the dashboard and a JSON snapshot', () async {
      app.useDevTools(enabled: true);
      app.get('/hello', (req) => Response.json({'hi': true}));
      await start();

      final dash = await send('GET', '/__dev');
      expect(dash.status, 200);
      expect(dash.headers.contentType?.mimeType, 'text/html');
      expect(dash.body, contains('dart_server'));

      await send('GET', '/hello?a=1');

      final api = jsonDecode((await send('GET', '/__dev/api')).body)
          as Map<String, dynamic>;
      expect(api['stats']['total'], greaterThanOrEqualTo(1));
      final requests = api['requests'] as List;
      final hello = requests.firstWhere((r) => r['path'] == '/hello');
      expect(hello['method'], 'GET');
      expect(hello['status'], 200);
      expect(hello['query'], {'a': '1'});

      final routes = (api['routes'] as List).map((r) => r['pattern']).toList();
      expect(routes, contains('/hello'));
      // The dashboard's own routes are excluded from the listing.
      expect(routes, isNot(contains('/__dev')));
    });

    test('records errored requests with their status', () async {
      app.useDevTools(enabled: true);
      app.get('/boom', (req) => throw HttpError.notFound('gone'));
      await start();

      await send('GET', '/boom');
      final api = jsonDecode((await send('GET', '/__dev/api')).body)
          as Map<String, dynamic>;
      final boom = (api['requests'] as List).firstWhere((r) => r['path'] == '/boom');
      expect(boom['status'], 404);
    });

    test('dashboard requests are not recorded, and clear empties the buffer',
        () async {
      app.useDevTools(enabled: true);
      app.get('/x', (req) => Response.text('x'));
      await start();

      await send('GET', '/x');
      await send('GET', '/__dev/api'); // should not be recorded

      var api = jsonDecode((await send('GET', '/__dev/api')).body)
          as Map<String, dynamic>;
      final paths =
          (api['requests'] as List).map((r) => r['path']).toSet();
      expect(paths, contains('/x'));
      expect(paths.any((p) => p.toString().startsWith('/__dev')), isFalse);

      await send('POST', '/__dev/api/clear');
      api = jsonDecode((await send('GET', '/__dev/api')).body)
          as Map<String, dynamic>;
      expect(api['requests'], isEmpty);
    });
  });

  group('concurrency', () {
    test('params are isolated across overlapping requests', () async {
      app.get('/users/:id', (req) async {
        // Yield so requests genuinely interleave before reading params.
        await Future<void>.delayed(Duration.zero);
        return Response.json({'id': req.params['id']});
      });
      await start();

      final responses = await Future.wait([
        send('GET', '/users/1'),
        send('GET', '/users/2'),
        send('GET', '/users/3'),
      ]);
      final ids = responses.map((r) => jsonDecode(r.body)['id']).toList();
      expect(ids, containsAll(['1', '2', '3']));
    });
  });
}
