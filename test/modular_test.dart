import 'dart:convert';
import 'dart:io';

import 'package:dart_server/dart_server.dart';
import 'package:test/test.dart';

// --- Test fixtures ---------------------------------------------------------

class Counter {
  int value = 0;
}

class Greeter {
  Greeter(this.counter);
  final Counter counter;
  String greet() => 'hello #${++counter.value}';
}

class InitService implements OnInit {
  bool initialized = false;
  @override
  Future<void> onInit() async => initialized = true;
}

class GreetController extends Controller {
  GreetController(this._greeter);
  final Greeter _greeter;

  @override
  String get basePath => '/greet';

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', (req) => Response.json({'message': _greeter.greet()}));
  }
}

class RootController extends Controller {
  @override
  void register(RouteRegistrar routes) {
    routes.get('/', (req) => Response.text('root'));
    routes.get('/health', (req) => Response.json({'status': 'ok'}));
  }
}

void main() {
  group('DI container', () {
    test('resolves a provider graph and injects into a controller', () async {
      final module = Module(
        providers: [
          Provider.singleton((i) => Counter()),
          Provider.singleton((i) => Greeter(i.get<Counter>())),
        ],
        controllers: [(i) => GreetController(i.get<Greeter>())],
      );

      final app = await DartServerFactory.create(module);
      final server =
          await app.listen(0, address: InternetAddress.loopbackIPv4, quiet: true);
      addTearDown(() => app.close(force: true));

      final body = await _get(server, '/greet');
      expect(jsonDecode(body), {'message': 'hello #1'});
    });

    test('singletons are shared across the whole app', () async {
      final probe = <Counter>[];
      final module = Module(
        providers: [Provider.singleton((i) => Counter())],
        controllers: [
          (i) {
            probe.add(i.get<Counter>());
            probe.add(i.get<Counter>());
            return RootController();
          },
        ],
      );
      await DartServerFactory.create(module);
      expect(identical(probe[0], probe[1]), isTrue);
    });

    test('transient providers create a new instance each resolve', () async {
      final probe = <Counter>[];
      final module = Module(
        providers: [Provider.transient((i) => Counter())],
        controllers: [
          (i) {
            probe.add(i.get<Counter>());
            probe.add(i.get<Counter>());
            return RootController();
          },
        ],
      );
      await DartServerFactory.create(module);
      expect(identical(probe[0], probe[1]), isFalse);
    });

    test('value providers return the supplied instance', () async {
      final config = Counter()..value = 42;
      late Counter resolved;
      final module = Module(
        providers: [Provider.value<Counter>(config)],
        controllers: [
          (i) {
            resolved = i.get<Counter>();
            return RootController();
          },
        ],
      );
      await DartServerFactory.create(module);
      expect(identical(resolved, config), isTrue);
    });

    test('OnInit hooks run during bootstrap', () async {
      final service = InitService();
      final module = Module(providers: [Provider.value<InitService>(service)]);
      expect(service.initialized, isFalse);
      await DartServerFactory.create(module);
      expect(service.initialized, isTrue);
    });

    test('missing provider throws a DiError', () async {
      final module = Module(
        controllers: [(i) => GreetController(i.get<Greeter>())],
      );
      expect(DartServerFactory.create(module), throwsA(isA<DiError>()));
    });

    test('circular dependency throws a DiError', () async {
      final module = Module(
        providers: [
          Provider.singleton<Greeter>((i) => Greeter(i.get<Counter>())),
          // Counter "depends on" Greeter, forming a cycle.
          Provider.singleton<Counter>((i) {
            i.get<Greeter>();
            return Counter();
          }),
        ],
      );
      expect(DartServerFactory.create(module), throwsA(isA<DiError>()));
    });
  });

  group('module encapsulation', () {
    test('an importer can use an exported provider', () async {
      final featureModule = Module(
        providers: [
          Provider.singleton((i) => Counter()),
          Provider.singleton((i) => Greeter(i.get<Counter>())),
        ],
        exports: [Greeter],
      );
      final appModule = Module(
        imports: [featureModule],
        controllers: [(i) => GreetController(i.get<Greeter>())],
      );

      final app = await DartServerFactory.create(appModule);
      final server =
          await app.listen(0, address: InternetAddress.loopbackIPv4, quiet: true);
      addTearDown(() => app.close(force: true));

      expect(jsonDecode(await _get(server, '/greet')), {'message': 'hello #1'});
    });

    test('a non-exported provider is hidden from importers', () async {
      final featureModule = Module(
        providers: [
          Provider.singleton((i) => Counter()),
          Provider.singleton((i) => Greeter(i.get<Counter>())),
        ],
        // Greeter is NOT exported.
        exports: [Counter],
      );
      final appModule = Module(
        imports: [featureModule],
        controllers: [(i) => GreetController(i.get<Greeter>())],
      );

      expect(DartServerFactory.create(appModule), throwsA(isA<DiError>()));
    });

    test('exporting a token the module does not provide throws', () async {
      final module = Module(exports: [Greeter]);
      expect(DartServerFactory.create(module), throwsA(isA<DiError>()));
    });

    test('a global module is visible without being imported', () async {
      final coreModule = Module(
        providers: [Provider.singleton((i) => Counter())],
        exports: [Counter],
        isGlobal: true,
      );
      final featureModule = Module(
        providers: [Provider.singleton((i) => Greeter(i.get<Counter>()))],
        controllers: [(i) => GreetController(i.get<Greeter>())],
      );
      final appModule = Module(imports: [coreModule, featureModule]);

      final app = await DartServerFactory.create(appModule);
      final server =
          await app.listen(0, address: InternetAddress.loopbackIPv4, quiet: true);
      addTearDown(() => app.close(force: true));

      expect(jsonDecode(await _get(server, '/greet')), {'message': 'hello #1'});
    });
  });

  group('controller routing', () {
    test('basePath is joined with each route path', () async {
      final module = Module(controllers: [(i) => RootController()]);
      final app = await DartServerFactory.create(module);
      final server =
          await app.listen(0, address: InternetAddress.loopbackIPv4, quiet: true);
      addTearDown(() => app.close(force: true));

      expect(await _get(server, '/'), 'root');
      expect(jsonDecode(await _get(server, '/health')), {'status': 'ok'});
    });

    test('path joining handles slashes correctly', () {
      expect(DartServerFactory.joinPaths('/users', '/:id'), '/users/:id');
      expect(DartServerFactory.joinPaths('/users', '/'), '/users');
      expect(DartServerFactory.joinPaths('', '/health'), '/health');
      expect(DartServerFactory.joinPaths('users', 'list'), '/users/list');
      expect(DartServerFactory.joinPaths('', '/'), '/');
    });
  });
}

Future<String> _get(HttpServer server, String path) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('http://${server.address.host}:${server.port}$path');
    final request = await client.getUrl(uri);
    final response = await request.close();
    return utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}
