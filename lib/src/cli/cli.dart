import 'dart:async';
import 'dart:io';

import 'console.dart';
import 'templates.dart' as templates;

/// CLI version, surfaced by `dart_server --version`.
const String cliVersion = '1.0.0';

/// Entry point for the `dart_server` command-line tool. Returns a process
/// exit code.
Future<int> runCli(List<String> argv) async {
  final console = Console();
  if (argv.isEmpty) {
    _printUsage(console);
    return 0;
  }

  final command = argv.first;
  final args = _Args.parse(argv.sublist(1));

  try {
    switch (command) {
      case 'help':
      case '-h':
      case '--help':
        _printUsage(console);
        return 0;
      case 'version':
      case '-v':
      case '--version':
        console.info('dart_server $cliVersion');
        return 0;
      case 'create':
      case 'new':
        return await _create(console, args);
      case 'dev':
        return await _run(console, args, production: false);
      case 'prod':
        return await _run(console, args, production: true);
      case 'run':
        return await _run(console, args, production: args.flag('prod'));
      default:
        if (command.startsWith('make:')) {
          return await _make(console, command.substring(5), args);
        }
        console.error('Unknown command: $command');
        _printUsage(console);
        return 64;
    }
  } catch (error) {
    console.error(error.toString());
    return 1;
  }
}

// ---------------------------------------------------------------------------
// create
// ---------------------------------------------------------------------------

Future<int> _create(Console console, _Args args) async {
  final rawName = args.first;
  if (rawName == null) {
    console.error('Usage: dart_server create <name> [--local <path>]');
    return 64;
  }
  final pkg = toSnakeCase(rawName);
  final dir = Directory(pkg);
  if (dir.existsSync() &&
      dir.listSync().isNotEmpty &&
      !args.flag('force')) {
    console.error('Directory "$pkg" already exists and is not empty. '
        'Use --force to write into it anyway.');
    return 1;
  }

  console.heading('Creating dart_server app: $pkg');

  final local = args.option('local');
  final dependency = local != null
      ? '  dart_server:\n    path: ${Directory(local).absolute.path}'
      : '  dart_server: ^1.0.0';

  final files = <String, String>{
    'pubspec.yaml': templates.projectPubspec(pkg, dependency),
    '.gitignore': templates.projectGitignore(),
    'analysis_options.yaml': templates.projectAnalysisOptions(),
    'README.md': templates.projectReadme(pkg),
    'bin/server.dart': templates.serverEntry(pkg),
    'lib/app_module.dart': templates.appModuleFile(pkg),
    'lib/app_controller.dart': templates.appControllerFile(pkg),
    'lib/modules/.gitkeep': '',
  };

  files.forEach((relative, content) {
    final file = File('${dir.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    console.created('$pkg/$relative');
  });

  if (!args.flag('no-pub-get')) {
    console.step('\nRunning dart pub get...');
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get'],
      workingDirectory: dir.path,
    );
    if (result.exitCode == 0) {
      console.success('Dependencies installed.');
    } else {
      console.warn('dart pub get failed — run it manually in ./$pkg');
      stderr.write(result.stderr);
    }
  }

  console.heading('Done! Next steps:');
  console.info('  cd $pkg');
  console.info('  dart_server dev');
  return 0;
}

// ---------------------------------------------------------------------------
// make:*
// ---------------------------------------------------------------------------

Future<int> _make(Console console, String type, _Args args) async {
  final root = _findProjectRoot();
  if (root == null) {
    console.error('Not inside a dart_server project '
        '(no pubspec.yaml found in this or any parent directory).');
    return 1;
  }
  final rawName = args.first;
  if (rawName == null) {
    console.error('Usage: dart_server make:$type <Name>');
    return 64;
  }

  switch (type) {
    case 'model':
      return _emitModel(console, root, args, rawName);
    case 'controller':
      return _emitController(console, root, args, rawName);
    case 'repository':
      return _emitRepository(console, root, args, rawName);
    case 'middleware':
      return _emitMiddleware(console, root, args, rawName);
    case 'service':
      return _emitService(console, root, args, rawName);
    case 'module':
      return _emitModule(console, root, args, rawName);
    case 'resource':
      return _emitResource(console, root, args, rawName);
    default:
      console.error('Unknown generator: make:$type');
      console.info('Available: model, controller, repository, service, '
          'module, middleware, resource');
      return 64;
  }
}

/// Feature folder for a resource, e.g. `lib/modules/post`.
String _featureDir(String base) => 'lib/modules/${toSnakeCase(base)}';

int _emitModel(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['model']);
  final snake = toSnakeCase(base);
  return _write(console, root, args,
      relative: '${_featureDir(base)}/$snake.dart',
      content: templates.modelFile(toPascalCase(base)));
}

int _emitController(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['controller']);
  final snake = toSnakeCase(base);
  return _write(console, root, args,
      relative: '${_featureDir(base)}/${snake}_controller.dart',
      content: templates.controllerFile(toPascalCase(base), snake));
}

int _emitRepository(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['repository']);
  final snake = toSnakeCase(base);
  return _write(console, root, args,
      relative: '${_featureDir(base)}/${snake}_repository.dart',
      content: templates.repositoryFile(toPascalCase(base), snake));
}

int _emitMiddleware(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['middleware']);
  return _write(console, root, args,
      relative: 'lib/middleware/${toSnakeCase(base)}_middleware.dart',
      content:
          templates.middlewareFile(toPascalCase(base), toCamelCase(base)));
}

int _emitService(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['service']);
  return _write(console, root, args,
      relative: '${_featureDir(base)}/${toSnakeCase(base)}_service.dart',
      content: templates.serviceFile(toPascalCase(base)));
}

int _emitModule(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['module']);
  final result = _write(console, root, args,
      relative: '${_featureDir(base)}/${toSnakeCase(base)}_module.dart',
      content: templates.moduleFile(toPascalCase(base), toCamelCase(base)));
  if (result == 0) _registerHint(console, base);
  return result;
}

int _emitResource(Console console, String root, _Args args, String name) {
  final base = _stripSuffix(name, const ['resource']);
  final dir = _featureDir(base);
  final pascal = toPascalCase(base);
  final camel = toCamelCase(base);
  final snake = toSnakeCase(base);

  final results = [
    _write(console, root, args,
        relative: '$dir/$snake.dart', content: templates.modelFile(pascal)),
    _write(console, root, args,
        relative: '$dir/${snake}_repository.dart',
        content: templates.resourceRepositoryFile(pascal, snake)),
    _write(console, root, args,
        relative: '$dir/${snake}_service.dart',
        content: templates.resourceServiceFile(pascal, snake)),
    _write(console, root, args,
        relative: '$dir/${snake}_controller.dart',
        content: templates.resourceControllerFile(pascal, snake)),
    _write(console, root, args,
        relative: '$dir/${snake}_module.dart',
        content: templates.resourceModuleFile(pascal, camel, snake)),
  ];
  if (results.any((code) => code == 0)) _registerHint(console, base);
  return results.every((code) => code == 0) ? 0 : 1;
}

/// Reminds the user to wire a new module into the root AppModule.
void _registerHint(Console console, String base) {
  final snake = toSnakeCase(base);
  final camel = toCamelCase(base);
  console.info('');
  console.step('Register it in lib/app_module.dart:');
  console.info("  import 'modules/$snake/${snake}_module.dart';");
  console.info('  Module appModule() => Module(imports: [${camel}Module()], '
      'controllers: [(i) => AppController()]);');
}

int _write(
  Console console,
  String root,
  _Args args, {
  required String relative,
  required String content,
}) {
  final file = File('$root/$relative');
  if (file.existsSync() && !args.flag('force')) {
    console.skipped('$relative (exists — use --force to overwrite)');
    return 1;
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  console.created(relative);
  return 0;
}

// ---------------------------------------------------------------------------
// dev / prod
// ---------------------------------------------------------------------------

Future<int> _run(
  Console console,
  _Args args, {
  required bool production,
}) async {
  final root = _findProjectRoot();
  if (root == null) {
    console.error('Not inside a dart_server project '
        '(no pubspec.yaml found in this or any parent directory).');
    return 1;
  }
  final entry = args.option('entry') ?? 'bin/server.dart';
  if (!File('$root/$entry').existsSync()) {
    console.error('Entry point not found: $entry');
    return 1;
  }

  final env = {'DART_SERVER_ENV': production ? 'production' : 'development'};
  final port = args.option('port');
  if (port != null) env['DART_SERVER_PORT'] = port;

  final watch = !production && !args.flag('no-watch');
  final mode = production ? 'production' : 'development';
  console.heading('Starting $mode server'
      '${port != null ? ' on port $port' : ''}'
      '${watch ? ' — watching lib/ and bin/ for changes' : ''}');

  return _spawnServer(console, root: root, entry: entry, env: env, watch: watch);
}

Future<int> _spawnServer(
  Console console, {
  required String root,
  required String entry,
  required Map<String, String> env,
  required bool watch,
}) async {
  final isDev = env['DART_SERVER_ENV'] == 'development';

  Future<Process> spawn() => Process.start(
        Platform.resolvedExecutable,
        ['run', if (isDev) '--enable-asserts', entry],
        workingDirectory: root,
        environment: env,
        mode: ProcessStartMode.inheritStdio,
      );

  if (!watch) {
    final process = await spawn();
    return process.exitCode;
  }

  Process? current = await spawn();
  Timer? debounce;
  var restarting = false;

  Future<void> restart() async {
    if (restarting) return;
    restarting = true;
    final old = current;
    if (old != null) {
      old.kill();
      await old.exitCode;
    }
    current = await spawn();
    restarting = false;
  }

  final subscriptions = <StreamSubscription<FileSystemEvent>>[];
  for (final name in const ['lib', 'bin']) {
    final dir = Directory('$root/$name');
    if (!dir.existsSync()) continue;
    subscriptions.add(
      dir.watch(recursive: true).listen((event) {
        if (!event.path.endsWith('.dart')) return;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 350), () {
          console.step('↻ change detected — restarting...');
          restart();
        });
      }),
    );
  }

  final done = Completer<int>();
  late final StreamSubscription<ProcessSignal> sigint;
  sigint = ProcessSignal.sigint.watch().listen((_) async {
    console.info('\nShutting down...');
    debounce?.cancel();
    current?.kill();
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    await sigint.cancel();
    if (!done.isCompleted) done.complete(0);
  });

  return done.future;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Walks up from the current directory to find the project root (the nearest
/// ancestor containing a `pubspec.yaml`), or `null`.
String? _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Removes a trailing role suffix (case-insensitive) so `make:controller
/// UserController` and `make:controller User` both yield `User`.
String _stripSuffix(String name, List<String> suffixes) {
  for (final suffix in suffixes) {
    if (name.length > suffix.length &&
        name.toLowerCase().endsWith(suffix.toLowerCase())) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// Splits an identifier into words across `_`, `-`, spaces and camelCase
/// boundaries. `userProfile`, `user_profile`, `User-Profile` -> `[user, profile]`.
List<String> _tokenize(String input) {
  final separated = input.replaceAll(RegExp(r'[\s\-_]+'), ' ').trim();
  final withBoundaries =
      separated.replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ');
  return withBoundaries
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
}

String _capitalize(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1).toLowerCase();

/// `user_profile` / `userProfile` -> `UserProfile`.
String toPascalCase(String input) => _tokenize(input).map(_capitalize).join();

/// `user_profile` / `UserProfile` -> `userProfile`.
String toCamelCase(String input) {
  final pascal = toPascalCase(input);
  return pascal.isEmpty ? pascal : pascal[0].toLowerCase() + pascal.substring(1);
}

/// `UserProfile` / `user-profile` -> `user_profile`.
String toSnakeCase(String input) =>
    _tokenize(input).map((word) => word.toLowerCase()).join('_');

void _printUsage(Console console) {
  final b = console.bold;
  console.info('''
${b('dart_server')} — CLI for the dart_server framework  (v$cliVersion)

${b('Usage')}
  dart_server <command> [arguments]

${b('Project')}
  create <name> [--local <path>] [--no-pub-get] [--force]
                         Scaffold a new dart_server app
  dev   [--port <n>] [--entry <file>] [--no-watch]
                         Run in development (dev dashboard + auto-restart)
  prod  [--port <n>] [--entry <file>]
                         Run in production

${b('Generators')}  ${console.dim('(feature files go in lib/modules/<name>/)')}
  make:resource <Name>     Full feature: model + repository + service +
                           controller + module
  make:module <Name>       Create a module
  make:controller <Name>   Create a controller
  make:service <Name>      Create a service
  make:repository <Name>   Create a repository
  make:model <Name>        Create a model
  make:middleware <Name>   Create a middleware   (lib/middleware)
  ${console.dim('(add --force to overwrite an existing file)')}

${b('Other')}
  help                   Show this help
  version                Show the CLI version

${b('Examples')}
  dart_server create blog
  dart_server make:resource Post
  dart_server dev --port 8080''');
}

/// Minimal positional/option/flag parser. Options take the next token as their
/// value unless that token starts with `-`; known booleans are always flags.
class _Args {
  _Args(this.positionals, this.options, this.flags);

  final List<String> positionals;
  final Map<String, String> options;
  final Set<String> flags;

  static const _booleanFlags = {
    'force',
    'no-watch',
    'no-pub-get',
    'prod',
    'watch',
    'help',
  };

  factory _Args.parse(List<String> argv) {
    final positionals = <String>[];
    final options = <String, String>{};
    final flags = <String>{};

    for (var i = 0; i < argv.length; i++) {
      final token = argv[i];
      if (!token.startsWith('--')) {
        positionals.add(token);
        continue;
      }
      final key = token.substring(2);
      if (key.contains('=')) {
        final parts = key.split('=');
        options[parts.first] = parts.sublist(1).join('=');
      } else if (_booleanFlags.contains(key)) {
        flags.add(key);
      } else if (i + 1 < argv.length && !argv[i + 1].startsWith('-')) {
        options[key] = argv[++i];
      } else {
        flags.add(key);
      }
    }
    return _Args(positionals, options, flags);
  }

  String? get first => positionals.isEmpty ? null : positionals.first;
  String? option(String key) => options[key];
  bool flag(String key) => flags.contains(key);
}
