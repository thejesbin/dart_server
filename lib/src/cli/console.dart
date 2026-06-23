import 'dart:io';

/// Small terminal-output helper for the CLI: colored, consistent status lines.
///
/// Colors are auto-disabled when stdout isn't a TTY or `NO_COLOR` is set.
class Console {
  Console({bool? color}) : _color = color ?? _supportsColor();

  final bool _color;

  static bool _supportsColor() {
    if (Platform.environment.containsKey('NO_COLOR')) return false;
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  }

  String _wrap(String code, String text) =>
      _color ? '\x1b[${code}m$text\x1b[0m' : text;

  /// Bold text (no newline added).
  String bold(String text) => _wrap('1', text);

  /// Dim text (no newline added).
  String dim(String text) => _wrap('2', text);

  /// A plain line.
  void info(String message) => stdout.writeln(message);

  /// A bold section heading, preceded by a blank line.
  void heading(String message) => stdout.writeln('\n${_wrap('1', message)}');

  /// A cyan progress/step line.
  void step(String message) => stdout.writeln(_wrap('36', message));

  /// A green success line.
  void success(String message) => stdout.writeln('${_wrap('32', '✓')} $message');

  /// A yellow warning line.
  void warn(String message) => stdout.writeln('${_wrap('33', '!')} $message');

  /// A red error line (to stderr).
  void error(String message) => stderr.writeln('${_wrap('31', '✗')} $message');

  /// "created  <path>" — a generated file.
  void created(String path) =>
      stdout.writeln('  ${_wrap('32', 'created')}  $path');

  /// "skipped  <path>" — an existing file left untouched.
  void skipped(String path) =>
      stdout.writeln('  ${_wrap('33', 'skipped')}  $path');
}
