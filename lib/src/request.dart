import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';

/// An incoming HTTP request, wrapping the raw [HttpRequest] with an
/// Express.js-style, developer-friendly API.
///
/// Instances are created by the framework via [Request.from] and handed to
/// route handlers and middleware. You should not normally construct a
/// [Request] yourself outside of tests.
///
/// ```dart
/// app.get('/users/:id', (req) {
///   print(req.method);        // GET
///   print(req.path);          // /users/42
///   print(req.params['id']);  // 42
///   print(req.query['sort']); // ?sort=asc  ->  asc
///   return Response.json({'id': req.params['id']});
/// });
/// ```
class Request {
  /// The raw underlying [HttpRequest], exposed for advanced use cases
  /// (streaming responses, cookies, certificates, websockets, etc.).
  ///
  /// Note: the request body stream has already been drained into [bodyBytes],
  /// so re-reading `raw` as a stream yields nothing. Use [bodyBytes] / [body]
  /// to access the payload.
  final HttpRequest raw;

  /// The HTTP method in upper case, e.g. `GET`, `POST`, `PUT`, `DELETE`.
  final String method;

  /// The request path without the query string, e.g. `/users/42`.
  final String path;

  /// Request headers as a flat, lower-cased map.
  ///
  /// Multi-valued headers are joined with `, `. For full access to the raw
  /// header collection use `raw.headers`.
  final Map<String, String> headers;

  /// Parsed query-string parameters, e.g. `/search?q=dart` -> `{'q': 'dart'}`.
  final Map<String, String> query;

  /// The raw request body as the exact bytes received, always preserved.
  ///
  /// Use this for binary payloads (file uploads, protobuf, etc.). For text or
  /// JSON prefer [body] / [json].
  final List<int> bodyBytes;

  /// Route parameters extracted from the matched path pattern.
  ///
  /// For a route declared as `/users/:id` matched against `/users/42`, this is
  /// `{'id': '42'}`. Populated by the framework just before the handler runs.
  Map<String, String> params;

  /// A free-form, per-request scratch space for sharing data between
  /// middleware and handlers (similar to attaching properties on Express's
  /// `req`). For example an auth middleware can set `req.context['user']`.
  final Map<String, dynamic> context;

  /// Cached UTF-8 decode of [bodyBytes].
  String? _bodyString;

  /// Cached parsed JSON body so repeated [json] calls are cheap.
  Object? _parsedJson;
  bool _jsonParsed = false;

  Request._({
    required this.raw,
    required this.method,
    required this.path,
    required this.headers,
    required this.query,
    required this.bodyBytes,
    Map<String, String>? params,
  })  : params = params ?? <String, String>{},
        context = <String, dynamic>{};

  /// Builds a [Request] from a raw [HttpRequest], fully reading and buffering
  /// the request body so handlers can access it synchronously via [body] /
  /// [bodyBytes] or parse it via [json].
  ///
  /// When [maxBodyBytes] is non-null, a body whose declared `Content-Length` or
  /// actual size exceeds it is rejected by throwing [HttpError] `413 Payload
  /// Too Large` — the framework turns that into a JSON error response.
  static Future<Request> from(HttpRequest raw, {int? maxBodyBytes}) async {
    final headers = <String, String>{};
    raw.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });

    final bytes = await _readBody(raw, maxBodyBytes);

    return Request._(
      raw: raw,
      method: raw.method.toUpperCase(),
      path: raw.uri.path,
      headers: headers,
      query: Map<String, String>.from(raw.uri.queryParameters),
      bodyBytes: bytes,
    );
  }

  /// Buffers the body bytes, enforcing [maxBodyBytes] both up-front (via the
  /// declared `Content-Length`) and while streaming (so a missing or dishonest
  /// length can't smuggle a large payload past the guard).
  static Future<List<int>> _readBody(HttpRequest raw, int? maxBodyBytes) async {
    if (maxBodyBytes != null && raw.contentLength > maxBodyBytes) {
      throw HttpError(413, 'Payload Too Large',
          details: {'maxBytes': maxBodyBytes});
    }
    // BytesBuilder keeps the buffer as byte data (vs a growable List<int>,
    // whose boxed elements would cost ~8x the body size on the 64-bit VM).
    final builder = BytesBuilder(copy: false);
    await for (final chunk in raw) {
      builder.add(chunk);
      if (maxBodyBytes != null && builder.length > maxBodyBytes) {
        throw HttpError(413, 'Payload Too Large',
            details: {'maxBytes': maxBodyBytes});
      }
    }
    return builder.takeBytes();
  }

  /// The request body decoded as a UTF-8 string (cached).
  ///
  /// Invalid byte sequences are replaced with the Unicode replacement
  /// character (U+FFFD) rather than throwing, and the original bytes remain
  /// available via [bodyBytes]. An empty body decodes to `''`.
  String get body =>
      _bodyString ??= utf8.decode(bodyBytes, allowMalformed: true);

  /// Parses and returns the request body as JSON.
  ///
  /// The decoded value (typically a `Map<String, dynamic>` or `List`) is cached
  /// so calling this multiple times does no extra work. Returns `null` for an
  /// empty body. Throws [FormatException] if the body is not valid JSON — and,
  /// because the result is only cached on success, an invalid body keeps
  /// throwing on every call rather than silently returning `null`.
  ///
  /// ```dart
  /// final data = await req.json();
  /// final email = data['email'];
  /// ```
  Future<dynamic> json() async {
    if (_jsonParsed) return _parsedJson;
    final text = body;
    final decoded = text.trim().isEmpty ? null : jsonDecode(text);
    // Only mark as parsed after a successful decode so malformed JSON re-throws.
    _parsedJson = decoded;
    _jsonParsed = true;
    return decoded;
  }

  /// Parses the request body as JSON and requires it to be a JSON object.
  ///
  /// Unlike [json], validation failures become client errors instead of
  /// `500`s: an invalid JSON body or a non-object body (array, string, …)
  /// throws [HttpError] `400 Bad Request`.
  ///
  /// ```dart
  /// final body = await req.jsonMap();
  /// final name = body['name'] as String?;
  /// ```
  Future<Map<String, dynamic>> jsonMap() async {
    final Object? decoded;
    try {
      decoded = await json();
    } on FormatException catch (e) {
      throw HttpError.badRequest('Invalid JSON body: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw HttpError.badRequest('Request body must be a JSON object');
    }
    return decoded;
  }

  /// The route parameter [name], throwing [HttpError] `400` if it's missing.
  String param(String name) {
    final value = params[name];
    if (value == null) {
      throw HttpError.badRequest('Missing route parameter "$name"');
    }
    return value;
  }

  /// The route parameter [name] parsed as an integer.
  ///
  /// Throws [HttpError] `400 Bad Request` when the parameter is missing or not
  /// an integer, so malformed client input never surfaces as a server error:
  ///
  /// ```dart
  /// final id = req.paramInt('id'); // /users/abc -> 400, not a 500
  /// ```
  int paramInt(String name) {
    final value = param(name);
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw HttpError.badRequest('Route parameter "$name" must be an integer');
    }
    return parsed;
  }

  /// The query parameter [name] parsed as an integer, or `null` if absent.
  /// Throws [HttpError] `400` if it's present but not an integer.
  int? queryInt(String name) {
    final value = query[name];
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw HttpError.badRequest('Query parameter "$name" must be an integer');
    }
    return parsed;
  }

  /// The query parameter [name] parsed as a boolean, or `null` if absent.
  ///
  /// Accepts `true`/`1`/`yes`/`on` and `false`/`0`/`no`/`off`
  /// (case-insensitive); anything else throws [HttpError] `400`.
  bool? queryBool(String name) {
    final value = query[name];
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'true' || '1' || 'yes' || 'on':
        return true;
      case 'false' || '0' || 'no' || 'off':
        return false;
    }
    throw HttpError.badRequest('Query parameter "$name" must be a boolean');
  }

  /// The value of the `Content-Type` header, or `null` if absent.
  String? get contentType => headers['content-type'];

  /// Whether the request advertises a JSON body via its `Content-Type`.
  bool get isJson => contentType?.contains('application/json') ?? false;

  @override
  String toString() => '$method $path';
}
