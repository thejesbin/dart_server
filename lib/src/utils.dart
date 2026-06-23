/// Internal helper utilities shared across the framework.
///
/// Nothing here is part of the public API surface — these are small, focused
/// helpers used by the router, request, response and middleware modules.
library;

/// A minimal extension-to-MIME-type lookup table.
///
/// Used by the static file middleware ([serveStatic]) to set a sensible
/// `Content-Type` header when serving files from disk. Keeping this as a plain
/// map avoids pulling in the `mime` package and keeps the dependency list at
/// zero, which is one of the framework's design goals.
const Map<String, String> _mimeTypes = {
  'html': 'text/html; charset=utf-8',
  'htm': 'text/html; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'js': 'application/javascript; charset=utf-8',
  'mjs': 'application/javascript; charset=utf-8',
  'json': 'application/json; charset=utf-8',
  'map': 'application/json; charset=utf-8',
  'xml': 'application/xml; charset=utf-8',
  'txt': 'text/plain; charset=utf-8',
  'csv': 'text/csv; charset=utf-8',
  'md': 'text/markdown; charset=utf-8',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'bmp': 'image/bmp',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'eot': 'application/vnd.ms-fontobject',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'wasm': 'application/wasm',
};

/// Returns a best-guess MIME type for [path] based on its file extension.
///
/// Falls back to `application/octet-stream` when the extension is unknown,
/// which is the safe default for arbitrary binary content.
String mimeTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot == path.length - 1) {
    return 'application/octet-stream';
  }
  final ext = path.substring(dot + 1).toLowerCase();
  return _mimeTypes[ext] ?? 'application/octet-stream';
}

/// Normalizes a URL path for routing comparisons.
///
/// * Collapses an empty path to `/`.
/// * Strips a single trailing slash (except for the root `/`) so that
///   `/users` and `/users/` resolve to the same route.
String normalizePath(String path) {
  if (path.isEmpty) return '/';
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// Splits a normalized path into its non-empty segments.
///
/// `/users/42` becomes `['users', '42']`; `/` becomes `[]`.
List<String> splitPath(String path) {
  return normalizePath(path)
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
}

/// Normalizes a filesystem path for safe static-file resolution.
///
/// Collapses `.` and `..` segments and removes empty/duplicate separators so
/// the result can be compared against a known root to defeat path-traversal
/// attempts. Returns a `/`-separated path without a trailing slash.
///
/// `/srv/public/../../etc/passwd` becomes `/etc/passwd`, which a caller can
/// then reject because it falls outside the served root.
String normalizeFilePath(String path) {
  final isAbsolute = path.startsWith('/');
  final result = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (result.isNotEmpty && result.last != '..') {
        result.removeLast();
      } else if (!isAbsolute) {
        result.add('..');
      }
      continue;
    }
    result.add(segment);
  }
  return (isAbsolute ? '/' : '') + result.join('/');
}
