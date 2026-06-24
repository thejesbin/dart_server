import 'package:dart_server/dart_server.dart';

import 'app_controller.dart';
import 'modules/users/users_module.dart';

/// The root module — the single entry point that [DartServerFactory] starts
/// from.
///
/// A module describes a slice of the app:
///   - `imports`     other modules whose exported providers become available
///                   here (this is how features are composed).
///   - `controllers` factory functions that build controllers, pulling their
///                   dependencies from the injector `i`.
///   - `providers`   the services this module owns (none at the root here).
///   - `exports`     which providers importers may inject.
///
/// To add a feature, generate it with `dart_server make:resource <Name>` and
/// add its `<name>Module()` to `imports` below.
Module appModule() => Module(
      imports: [usersModule()],
      controllers: [(i) => AppController()],
    );
