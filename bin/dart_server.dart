import 'dart:io';

import 'package:dart_server/src/cli/cli.dart';

/// The `dart_server` command-line tool.
///
/// Install it globally with `dart pub global activate dart_server`, or run it
/// inside a project that depends on dart_server via
/// `dart run dart_server:dart_server <command>`.
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
