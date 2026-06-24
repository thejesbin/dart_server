import 'package:dart_server/dart_server.dart';

import 'users_controller.dart';
import 'users_service.dart';

/// The Users feature module — the unit that ties one feature together.
///
/// A module declares:
///   - `providers`   the injectable services it owns. `Provider.singleton`
///                   registers one shared instance for the whole app.
///   - `controllers` factory functions that build each controller, pulling
///                   dependencies out of the injector with `i.get<T>()`.
///   - `exports`     which providers other modules may inject after importing
///                   this one. Anything not exported stays private to the
///                   module — that's the encapsulation boundary.
Module usersModule() => Module(
      // Register UsersService; the injector hands the same instance to anyone
      // that asks for `UsersService`.
      providers: [Provider.singleton((i) => UsersService())],
      // Build the controller, injecting the service it needs.
      controllers: [(i) => UsersController(i.get<UsersService>())],
      // Make UsersService injectable by modules that import this one.
      exports: [UsersService],
    );
