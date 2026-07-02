import 'dart:io';

/// Application configuration read from a `.env` file and the process
/// environment, with zero dependencies — one typed object your services can
/// inject instead of touching `Platform.environment` directly.
///
/// [Env.load] reads an env file (if present) and merges in
/// [Platform.environment], with the real environment winning on conflicts —
/// the standard dotenv precedence, so deployments can override file values.
///
/// ```dart
/// final env = Env.load();                    // reads .env + process env
/// final port = env.getInt('PORT') ?? 3000;
/// final dbUrl = env.require('DATABASE_URL'); // throws if missing
/// if (env.getBool('FEATURE_X') ?? false) { ... }
/// ```
///
/// Register it as a provider so anything in the module graph can inject it:
///
/// ```dart
/// Module appModule() => Module(
///       providers: [Provider.singleton((i) => Env.load())],
///       ...
///     );
/// ```
///
/// Supported `.env` syntax: one `KEY=VALUE` per line, full-line `#` comments,
/// an optional `export ` prefix, and values wrapped in single or double quotes
/// (the quotes are stripped, and a `# comment` after the closing quote is
/// dropped). Unquoted values are taken verbatim to the end of the line —
/// including any `#` — and values are not otherwise interpolated.
class Env {
  Env._(this._values);

  /// Builds an [Env] from an in-memory map — handy in tests.
  factory Env.fromMap(Map<String, String> values) =>
      Env._(Map.unmodifiable(values));

  /// Loads configuration from [envFile] (skipped if it doesn't exist) merged
  /// with [Platform.environment] (which takes precedence) unless
  /// [includePlatformEnvironment] is `false`.
  factory Env.load({
    String envFile = '.env',
    bool includePlatformEnvironment = true,
  }) {
    final values = <String, String>{};
    final file = File(envFile);
    if (file.existsSync()) {
      for (var line in file.readAsLinesSync()) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith('export ')) line = line.substring(7).trim();
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        var value = line.substring(eq + 1).trim();
        // Quoted value: take the quoted contents and drop anything after the
        // closing quote when it's (or precedes) a `#` comment.
        if (value.length >= 2 && (value[0] == '"' || value[0] == "'")) {
          final quote = value[0];
          final closing = value.indexOf(quote, 1);
          if (closing > 0) {
            final rest = value.substring(closing + 1).trimLeft();
            if (rest.isEmpty || rest.startsWith('#')) {
              value = value.substring(1, closing);
            }
          }
        }
        values[key] = value;
      }
    }
    if (includePlatformEnvironment) values.addAll(Platform.environment);
    return Env._(Map.unmodifiable(values));
  }

  final Map<String, String> _values;

  /// The value for [key], or `null` if it isn't set.
  String? operator [](String key) => _values[key];

  /// The value for [key], or `null` if it isn't set.
  String? get(String key) => _values[key];

  /// The value for [key]; throws [StateError] naming the key if it's missing.
  String require(String key) {
    final value = _values[key];
    if (value == null) {
      throw StateError('Missing required environment variable "$key"');
    }
    return value;
  }

  /// The value for [key] parsed as an integer, or `null` if it isn't set.
  /// Throws [FormatException] if the value is set but not an integer.
  int? getInt(String key) {
    final value = _values[key];
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException('Env value for "$key" is not an integer: "$value"');
    }
    return parsed;
  }

  /// The value for [key] parsed as a boolean, or `null` if it isn't set.
  ///
  /// Accepts `true`/`1`/`yes`/`on` and `false`/`0`/`no`/`off`
  /// (case-insensitive); anything else throws [FormatException].
  bool? getBool(String key) {
    final value = _values[key];
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'true' || '1' || 'yes' || 'on':
        return true;
      case 'false' || '0' || 'no' || 'off':
        return false;
    }
    throw FormatException('Env value for "$key" is not a boolean: "$value"');
  }

  /// All values as an unmodifiable map.
  Map<String, String> toMap() => _values;

  /// Whether [key] is set.
  bool has(String key) => _values.containsKey(key);
}
