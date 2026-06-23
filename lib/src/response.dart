import 'dart:convert';
import 'dart:io';

/// An outgoing HTTP response.
///
/// Build responses with the convenience factory constructors and return them
/// from handlers and middleware. The framework takes care of writing the
/// status line, headers and body to the socket.
///
/// ```dart
/// Response.json({'ok': true});          // 200, application/json
/// Response.text('Hello');               // 200, text/plain
/// Response.status(201, {'id': 1});      // 201, application/json
/// Response.status(204);                 // 204, empty body
/// ```
class Response {
  /// The HTTP status code, e.g. `200`, `404`, `500`.
  int statusCode;

  /// Response headers. Keys are case-insensitive at the socket layer.
  final Map<String, String> headers;

  /// The response payload encoded as bytes.
  List<int> bodyBytes;

  /// The `Content-Type` for the response, written as a structured header.
  ContentType? contentType;

  Response._({
    required this.statusCode,
    required this.bodyBytes,
    this.contentType,
    Map<String, String>? headers,
  }) : headers = headers ?? <String, String>{};

  /// Creates a JSON response by encoding [data] with [jsonEncode].
  ///
  /// Sets `Content-Type: application/json; charset=utf-8`.
  factory Response.json(
    Object? data, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    return Response._(
      statusCode: status,
      bodyBytes: utf8.encode(jsonEncode(data)),
      contentType: ContentType('application', 'json', charset: 'utf-8'),
      headers: headers,
    );
  }

  /// Creates a plain-text response.
  ///
  /// Sets `Content-Type: text/plain; charset=utf-8`.
  factory Response.text(
    String text, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    return Response._(
      statusCode: status,
      bodyBytes: utf8.encode(text),
      contentType: ContentType.text,
      headers: headers,
    );
  }

  /// Creates an HTML response.
  ///
  /// Sets `Content-Type: text/html; charset=utf-8`.
  factory Response.html(
    String html, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    return Response._(
      statusCode: status,
      bodyBytes: utf8.encode(html),
      contentType: ContentType.html,
      headers: headers,
    );
  }

  /// Creates a response with an explicit status [code] and optional [data].
  ///
  /// * If [data] is `null`, an empty body is sent (useful for `204 No Content`).
  /// * If [data] is a [String], it is sent as plain text.
  /// * Otherwise [data] is JSON-encoded.
  ///
  /// ```dart
  /// Response.status(201, {'created': true});
  /// Response.status(204);
  /// ```
  factory Response.status(int code, [Object? data]) {
    if (data == null) {
      return Response._(statusCode: code, bodyBytes: const []);
    }
    if (data is String) {
      return Response.text(data, status: code);
    }
    return Response.json(data, status: code);
  }

  /// Creates a raw byte response, e.g. for serving files or binary content.
  factory Response.bytes(
    List<int> bytes, {
    int status = 200,
    ContentType? contentType,
    Map<String, String>? headers,
  }) {
    return Response._(
      statusCode: status,
      bodyBytes: bytes,
      contentType: contentType,
      headers: headers,
    );
  }

  /// Issues an HTTP redirect to [location] with the given [status]
  /// (defaults to `302 Found`).
  factory Response.redirect(String location, {int status = 302}) {
    return Response._(
      statusCode: status,
      bodyBytes: const [],
      headers: {'location': location},
    );
  }

  /// Sets a header and returns `this` for fluent chaining.
  ///
  /// ```dart
  /// return Response.json(data).header('X-Total-Count', '42');
  /// ```
  Response header(String key, String value) {
    headers[key] = value;
    return this;
  }

  /// Writes this response to the underlying [httpResponse] and closes it.
  ///
  /// Called by the framework; you normally don't invoke this directly. When
  /// [head] is `true` (the request method was `HEAD`) the entity body is
  /// suppressed but the `Content-Length` it *would* have had is still sent, per
  /// RFC 9110. Bodiless statuses (`204`, `304`, `1xx`) carry neither a body nor
  /// a `Content-Length`.
  Future<void> writeTo(HttpResponse httpResponse, {bool head = false}) async {
    httpResponse.statusCode = statusCode;
    headers.forEach(httpResponse.headers.set);
    if (contentType != null) {
      httpResponse.headers.contentType = contentType;
    }
    if (_isBodiless(statusCode)) {
      // 204/304/1xx must not carry a body or a Content-Length.
      await httpResponse.close();
      return;
    }
    httpResponse.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length);
    if (!head) httpResponse.add(bodyBytes);
    await httpResponse.close();
  }

  /// Whether [code] denotes a response that must not include a message body.
  static bool _isBodiless(int code) =>
      code == 204 || code == 304 || (code >= 100 && code < 200);
}
