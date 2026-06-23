/// An exception that carries an HTTP status code.
///
/// Throw one of these from a handler or middleware to abort the request with a
/// specific status and a JSON error body — the framework catches it and writes
/// the response for you:
///
/// ```dart
/// app.get('/users/:id', (req) async {
///   final user = await db.find(req.params['id']);
///   if (user == null) throw HttpError.notFound('No such user');
///   return Response.json(user);
/// });
/// // -> 404 {"error": "No such user", "statusCode": 404}
/// ```
class HttpError implements Exception {
  /// The HTTP status code to respond with, e.g. `400`, `404`, `500`.
  final int statusCode;

  /// A human-readable message included in the JSON body under `"error"`.
  final String message;

  /// Optional extra structured data included under `"details"`.
  final Object? details;

  /// Creates an [HttpError] with an explicit [statusCode] and [message].
  HttpError(this.statusCode, this.message, {this.details});

  /// `400 Bad Request`.
  factory HttpError.badRequest([String message = 'Bad Request', Object? details]) =>
      HttpError(400, message, details: details);

  /// `401 Unauthorized`.
  factory HttpError.unauthorized([String message = 'Unauthorized', Object? details]) =>
      HttpError(401, message, details: details);

  /// `403 Forbidden`.
  factory HttpError.forbidden([String message = 'Forbidden', Object? details]) =>
      HttpError(403, message, details: details);

  /// `404 Not Found`.
  factory HttpError.notFound([String message = 'Not Found', Object? details]) =>
      HttpError(404, message, details: details);

  /// `409 Conflict`.
  factory HttpError.conflict([String message = 'Conflict', Object? details]) =>
      HttpError(409, message, details: details);

  /// `422 Unprocessable Entity`.
  factory HttpError.unprocessable(
          [String message = 'Unprocessable Entity', Object? details]) =>
      HttpError(422, message, details: details);

  /// `500 Internal Server Error`.
  factory HttpError.internal(
          [String message = 'Internal Server Error', Object? details]) =>
      HttpError(500, message, details: details);

  /// The JSON body this error serializes to.
  Map<String, dynamic> toJson() => {
        'error': message,
        if (details != null) 'details': details,
        'statusCode': statusCode,
      };

  @override
  String toString() => 'HttpError($statusCode): $message';
}
