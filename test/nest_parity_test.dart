import 'dart:convert';
import 'dart:io';

import 'package:dart_server/dart_server.dart';
import 'package:test/test.dart';

// --- Fixtures ----------------------------------------------------------------

class ApiKeyGuard implements Guard {
  @override
  bool canActivate(Request req) => req.headers['x-api-key'] == 'secret';
}

class ThrowingGuard implements Guard {
  @override
  bool canActivate(Request req) =>
      throw HttpError.unauthorized('token expired');
}

class ProbeController extends Controller {
  ProbeController({
    this.controllerGuards = const [],
    this.controllerMiddleware = const [],
    this.controllerInterceptors = const [],
    this.controllerFilters = const [],
    this.routeGuards = const [],
    this.routeMiddleware = const [],
    this.routeInterceptors = const [],
    this.routeFilters = const [],
    Handler? handler,
  }) : handler = handler ?? ((req) => Response.json({'ok': true}));

  final List<Guard> controllerGuards;
  final List<Middleware> controllerMiddleware;
  final List<Middleware> controllerInterceptors;
  final List<ExceptionFilter> controllerFilters;
  final List<Guard> routeGuards;
  final List<Middleware> routeMiddleware;
  final List<Middleware> routeInterceptors;
  final List<ExceptionFilter> routeFilters;
  final Handler handler;

  @override
  List<Guard> get guards => controllerGuards;
  @override
  List<Middleware> get middleware => controllerMiddleware;
  @override
  List<Middleware> get interceptors => controllerInterceptors;
  @override
  List<ExceptionFilter> get filters => controllerFilters;

  @override
  String get basePath => '/probe';

  @override
  void register(RouteRegistrar routes) {
    routes.get(
      '/',
      handler,
      guards: routeGuards,
      middleware: routeMiddleware,
      interceptors: routeInterceptors,
      filters: routeFilters,
    );
  }
}

class ShutdownProbe implements OnShutdown {
  ShutdownProbe(this.name, this.log, {this.throws = false});
  final String name;
  final List<String> log;
  final bool throws;

  @override
  Future<void> onShutdown() async {
    log.add(name);
    if (throws) throw StateError('boom in $name');
  }
}

void main() {
  HttpClient? client;
  DartServer? app;

  tearDown(() async {
    client?.close(force: true);
    await app?.close(force: true);
  });

  Future<HttpServer> start(DartServer server) async {
    app = server;
    client = HttpClient();
    return server.listen(0, address: InternetAddress.loopbackIPv4, quiet: true);
  }

  Future<({int status, String body})> get(
    HttpServer server,
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse('http://${server.address.host}:${server.port}$path');
    final request = await client!.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  group('guards', () {
    test('route guard blocks with 403 and allows with the right header',
        () async {
      final module = Module(controllers: [
        (i) => ProbeController(routeGuards: [ApiKeyGuard()]),
      ]);
      final server = await start(await DartServerFactory.create(module));

      expect((await get(server, '/probe')).status, 403);
      final ok = await get(server, '/probe', headers: {'x-api-key': 'secret'});
      expect(ok.status, 200);
    });

    test('a guard may throw its own HttpError (401)', () async {
      final module = Module(controllers: [
        (i) => ProbeController(routeGuards: [ThrowingGuard()]),
      ]);
      final server = await start(await DartServerFactory.create(module));

      final res = await get(server, '/probe');
      expect(res.status, 401);
      expect(jsonDecode(res.body)['error'], 'token expired');
    });

    test('controller-level and global guards apply; Guard.from works',
        () async {
      final module = Module(controllers: [
        (i) => ProbeController(
              controllerGuards: [
                Guard.from((req) => req.headers['x-ctrl'] == 'yes'),
              ],
            ),
      ]);
      final appServer = await DartServerFactory.create(
        module,
        guards: [Guard.from((req) => req.headers['x-global'] == 'yes')],
      );
      final server = await start(appServer);

      expect((await get(server, '/probe')).status, 403);
      expect(
        (await get(server, '/probe', headers: {'x-global': 'yes'})).status,
        403,
        reason: 'controller guard still blocks',
      );
      expect(
        (await get(server, '/probe',
                headers: {'x-global': 'yes', 'x-ctrl': 'yes'}))
            .status,
        200,
      );
    });
  });

  group('pipeline order', () {
    test(
        'controller mw -> route mw -> guards -> interceptors -> handler; '
        'interceptors do not run when a guard blocks', () async {
      final order = <String>[];
      Middleware tag(String name) => (req, next) {
            order.add(name);
            return next();
          };

      final module = Module(controllers: [
        (i) => ProbeController(
              controllerMiddleware: [tag('ctrl-mw')],
              routeMiddleware: [tag('route-mw')],
              controllerInterceptors: [tag('ctrl-icp')],
              routeInterceptors: [tag('route-icp')],
              routeGuards: [
                Guard.from((req) {
                  order.add('guard');
                  return req.headers['x-ok'] == 'yes';
                }),
              ],
              handler: (req) {
                order.add('handler');
                return Response.text('done');
              },
            ),
      ]);
      final server = await start(await DartServerFactory.create(module));

      await get(server, '/probe', headers: {'x-ok': 'yes'});
      expect(order,
          ['ctrl-mw', 'route-mw', 'guard', 'ctrl-icp', 'route-icp', 'handler']);

      order.clear();
      final blocked = await get(server, '/probe');
      expect(blocked.status, 403);
      expect(order, ['ctrl-mw', 'route-mw', 'guard'],
          reason: 'interceptors and handler must not run after a guard blocks');
    });

    test('an interceptor can transform the response', () async {
      final module = Module(controllers: [
        (i) => ProbeController(
              routeInterceptors: [
                (req, next) async =>
                    (await next()).header('x-intercepted', 'yes'),
              ],
            ),
      ]);
      final server = await start(await DartServerFactory.create(module));

      final uri =
          Uri.parse('http://${server.address.host}:${server.port}/probe');
      final response = await (await client!.getUrl(uri)).close();
      expect(response.headers.value('x-intercepted'), 'yes');
    });
  });

  group('exception filters', () {
    ExceptionFilter tagFilter(String name, List<String> tried,
            {bool handles = false}) =>
        ExceptionFilter.from((req, error, st) {
          tried.add(name);
          return handles
              ? Response.json({'handledBy': name}, status: 502)
              : null;
        });

    test('route filter handles first; null declines to controller then global',
        () async {
      final tried = <String>[];
      final module = Module(controllers: [
        (i) => ProbeController(
              handler: (req) => throw StateError('kaboom'),
              routeFilters: [tagFilter('route', tried)],
              controllerFilters: [tagFilter('controller', tried)],
            ),
      ]);
      final appServer = await DartServerFactory.create(
        module,
        filters: [tagFilter('global', tried, handles: true)],
      );
      final server = await start(appServer);

      final res = await get(server, '/probe');
      expect(tried, ['route', 'controller', 'global']);
      expect(res.status, 502);
      expect(jsonDecode(res.body)['handledBy'], 'global');
    });

    test('unhandled errors fall through to the built-in HttpError mapping',
        () async {
      final module = Module(controllers: [
        (i) => ProbeController(
              handler: (req) => throw HttpError.notFound('gone'),
              routeFilters: [
                ExceptionFilter.from((req, error, st) => null), // declines
              ],
            ),
      ]);
      final server = await start(await DartServerFactory.create(module));

      final res = await get(server, '/probe');
      expect(res.status, 404, reason: 'HttpError mapping still applies');
    });

    test('filters catch guard rejections too', () async {
      final module = Module(controllers: [
        (i) => ProbeController(
              routeGuards: [Guard.from((req) => false)],
              controllerFilters: [
                ExceptionFilter.from((req, error, st) =>
                    error is HttpError && error.statusCode == 403
                        ? Response.json({'softened': true}, status: 200)
                        : null),
              ],
            ),
      ]);
      final server = await start(await DartServerFactory.create(module));

      final res = await get(server, '/probe');
      expect(res.status, 200);
      expect(jsonDecode(res.body), {'softened': true});
    });

    test('errors thrown by scoped middleware skip the filters', () async {
      var filterRan = false;
      final module = Module(controllers: [
        (i) => ProbeController(
              routeMiddleware: [
                (req, next) => throw StateError('mw boom'),
              ],
              controllerFilters: [
                ExceptionFilter.from((req, error, st) {
                  filterRan = true;
                  return Response.text('handled');
                }),
              ],
            ),
      ]);
      final server = await start(await DartServerFactory.create(module));

      final res = await get(server, '/probe');
      expect(res.status, 500, reason: 'falls to the built-in mapping');
      expect(filterRan, isFalse);
    });
  });

  group('OnShutdown', () {
    test('hooks run on close in reverse creation order, exactly once',
        () async {
      final log = <String>[];
      final module = Module(providers: [
        Provider.singleton((i) => ShutdownProbe('first', log)),
        Provider.singleton(
            (i) => _Second(i.get<ShutdownProbe>(), log)), // depends on first
      ]);
      final appServer = await DartServerFactory.create(module);

      expect(log, isEmpty);
      await appServer.close();
      expect(log, ['second', 'first'],
          reason: 'dependents tear down before dependencies');

      await appServer.close(); // double close
      expect(log, ['second', 'first'], reason: 'hooks must not run twice');
    });

    test('a throwing hook does not stop the remaining hooks', () async {
      final log = <String>[];
      final module = Module(providers: [
        Provider.singleton((i) => ShutdownProbe('a', log)),
        Provider.singleton(
            (i) => _Chained(i.get<ShutdownProbe>(), 'b', log, throws: true)),
      ]);
      final appServer = await DartServerFactory.create(module);
      await appServer.close();
      expect(log, ['b', 'a']);
    });

    test('concurrent close() calls share one teardown (no crash, hooks once)',
        () async {
      final log = <String>[];
      final module = Module(
          providers: [Provider.singleton((i) => ShutdownProbe('x', log))]);
      final appServer = await DartServerFactory.create(module);
      await appServer.listen(0,
          address: InternetAddress.loopbackIPv4, quiet: true);

      await Future.wait([
        appServer.close(),
        appServer.close(),
        appServer.close(force: true),
      ]);
      expect(log, ['x']);
    });

    test('graceful close waits for in-flight requests before running hooks',
        () async {
      final events = <String>[];
      final appServer = DartServer();
      appServer.get('/slow', (req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        events.add('handler-done');
        return Response.text('ok');
      });
      appServer.addShutdownHook(() async => events.add('hook'));
      final server = await appServer.listen(0,
          address: InternetAddress.loopbackIPv4, quiet: true);

      final localClient = HttpClient();
      addTearDown(() => localClient.close(force: true));
      final uri =
          Uri.parse('http://${server.address.host}:${server.port}/slow');
      final pending =
          localClient.getUrl(uri).then((r) => r.close()); // in flight
      await Future<void>.delayed(const Duration(milliseconds: 80));

      await appServer.close(); // graceful: must drain first
      expect(events, ['handler-done', 'hook'],
          reason: 'shutdown hooks must run only after in-flight requests end');
      await pending;
    });
  });

  group('Env', () {
    test('parses a .env file: comments, quotes, export prefix', () async {
      final dir = await Directory.systemTemp.createTemp('dart_server_env');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/.env');
      await file.writeAsString('''
# a comment
APP_NAME="My App"
export TOKEN='abc123'
PORT=8080
EMPTY=
FLAG=on
BAD LINE IGNORED
''');
      final env =
          Env.load(envFile: file.path, includePlatformEnvironment: false);
      expect(env['APP_NAME'], 'My App');
      expect(env['TOKEN'], 'abc123');
      expect(env.getInt('PORT'), 8080);
      expect(env['EMPTY'], '');
      expect(env.getBool('FLAG'), isTrue);
      expect(env.has('BAD LINE IGNORED'), isFalse);
    });

    test('the real environment wins over the .env file', () async {
      final dir = await Directory.systemTemp.createTemp('dart_server_env');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/.env');
      await file.writeAsString('PATH=not-the-real-path\n');
      final env = Env.load(envFile: file.path);
      expect(env['PATH'], Platform.environment['PATH']);
    });

    test('require / getInt / getBool failure semantics', () {
      final env = Env.fromMap({'N': 'abc', 'B': 'maybe'});
      expect(() => env.require('MISSING'), throwsStateError);
      expect(() => env.getInt('N'), throwsFormatException);
      expect(() => env.getBool('B'), throwsFormatException);
      expect(env.getInt('MISSING'), isNull);
      expect(env.getBool('MISSING'), isNull);
    });

    test('quoted values with trailing comments are unquoted correctly',
        () async {
      final dir = await Directory.systemTemp.createTemp('dart_server_env');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/.env');
      await file.writeAsString('''
NAME="My App" # display name
URL='https://x.example/#anchor'
PLAIN=foo # kept verbatim for unquoted values
''');
      final env =
          Env.load(envFile: file.path, includePlatformEnvironment: false);
      expect(env['NAME'], 'My App');
      expect(env['URL'], 'https://x.example/#anchor');
      expect(env['PLAIN'], 'foo # kept verbatim for unquoted values');
    });
  });

  group('OnInit edge cases', () {
    test('an onInit that resolves a transient via its injector is safe',
        () async {
      final module = Module(providers: [
        Provider.transient((i) => Counter2()),
        Provider.singleton((i) => LateResolver(i)),
      ]);
      final appServer = await DartServerFactory.create(module);
      await appServer.close();
    });
  });

  group('joinPaths', () {
    test("a '/' basePath mounts at the root without double slashes", () {
      expect(DartServerFactory.joinPaths('/', '/health'), '/health');
      expect(DartServerFactory.joinPaths('/', '/'), '/');
    });
  });

  group('typed request helpers', () {
    test('paramInt: 400 on a non-integer param; parses valid ones', () async {
      final appServer = DartServer();
      appServer.get(
          '/users/:id', (req) => Response.json({'id': req.paramInt('id')}));
      final server = await start(appServer);

      final ok = await get(server, '/users/42');
      expect(jsonDecode(ok.body), {'id': 42});
      expect((await get(server, '/users/abc')).status, 400);
    });

    test('queryInt / queryBool: null when absent, 400 on garbage', () async {
      final appServer = DartServer();
      appServer.get(
          '/search',
          (req) => Response.json({
                'page': req.queryInt('page'),
                'exact': req.queryBool('exact'),
              }));
      final server = await start(appServer);

      expect(jsonDecode((await get(server, '/search')).body),
          {'page': null, 'exact': null});
      expect(jsonDecode((await get(server, '/search?page=2&exact=yes')).body),
          {'page': 2, 'exact': true});
      expect((await get(server, '/search?page=two')).status, 400);
      expect((await get(server, '/search?exact=perhaps')).status, 400);
    });

    test('jsonMap: 400 on invalid JSON and on non-object bodies', () async {
      final appServer = DartServer();
      appServer.post('/x', (req) async => Response.json(await req.jsonMap()));
      final server = await start(appServer);

      Future<int> post(String body) async {
        final uri = Uri.parse('http://${server.address.host}:${server.port}/x');
        final request = await client!.postUrl(uri);
        request.headers.contentType = ContentType('application', 'json');
        request.write(body);
        return (await request.close()).statusCode;
      }

      expect(await post('{"a": 1}'), 200);
      expect(await post('{broken'), 400);
      expect(await post('[1, 2, 3]'), 400);
    });
  });
}

class _Second implements OnShutdown {
  _Second(ShutdownProbe dependency, this.log);
  final List<String> log;

  @override
  Future<void> onShutdown() async => log.add('second');
}

class _Chained implements OnShutdown {
  _Chained(ShutdownProbe dependency, this.name, this.log,
      {required this.throws});
  final String name;
  final List<String> log;
  final bool throws;

  @override
  Future<void> onShutdown() async {
    log.add(name);
    if (throws) throw StateError('boom');
  }
}

class Counter2 {}

/// Keeps its [Injector] and resolves a transient inside onInit — used to pin
/// that bootstrap survives instances created during the OnInit pass.
class LateResolver implements OnInit {
  LateResolver(this._injector);
  final Injector _injector;

  @override
  Future<void> onInit() async {
    _injector.get<Counter2>();
  }
}
