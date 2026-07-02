import 'dart:io';

import 'package:dart_server/dart_server.dart';

/// A provider — an injectable class that holds logic and/or state.
///
/// It's registered in [usersModule] as a singleton, so dart_server creates one
/// instance and injects that same instance everywhere it's requested (here,
/// into the users controller).
///
/// Lifecycle hooks are optional interfaces:
/// * [OnInit] — `onInit()` is awaited once during bootstrap, after the
///   dependency graph is wired. Seed data or open connections here.
/// * [OnShutdown] — `onShutdown()` is awaited when the app closes (via
///   `app.close()` or, with `app.enableShutdownHooks()`, on Ctrl-C/SIGTERM).
///   Drain pools and flush buffers here.
class UsersService implements OnInit, OnShutdown {
  // In-memory store standing in for a database; `_nextId` mimics auto-increment.
  final List<Map<String, dynamic>> _users = [];
  int _nextId = 1;

  /// Runs once at startup (see [OnInit]); seeds a couple of users.
  @override
  Future<void> onInit() async {
    create('Ada Lovelace');
    create('Alan Turing');
  }

  /// Runs once at shutdown (see [OnShutdown]); a real app would close its
  /// database connection here.
  @override
  Future<void> onShutdown() async {
    stdout.writeln('[users] store closed (${_users.length} users at exit)');
  }

  /// All users, as an unmodifiable view so callers can't mutate the store.
  List<Map<String, dynamic>> all() => List.unmodifiable(_users);

  /// The user with the given [id], or `null` if there isn't one.
  Map<String, dynamic>? find(int id) {
    for (final user in _users) {
      if (user['id'] == id) return user;
    }
    return null;
  }

  /// Adds a new user with [name], assigns it an id, and returns it.
  Map<String, dynamic> create(String name) {
    final user = {'id': _nextId++, 'name': name};
    _users.add(user);
    return user;
  }
}
