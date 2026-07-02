/// OpenAPI 3 documentation support: describe routes with [ApiDoc], build the
/// specification from the live route table, and serve interactive docs.
///
/// The base specification is generated automatically from every registered
/// route (method, path, path parameters). Routes opt into richer docs by
/// passing a `doc:` argument — no annotations or code generation involved:
///
/// ```dart
/// routes.get('/:id', show,
///     doc: ApiDoc(
///       summary: 'Fetch one user',
///       params: {'id': ApiParam(description: 'User id')},
///       responses: {
///         200: ApiResponse('The user', schema: userSchema),
///         404: ApiResponse('No such user'),
///       },
///     ));
/// ```
///
/// Mount everything with `app.useOpenApi(title: 'My API')` — the JSON
/// specification is served at `/docs/openapi.json` and an interactive
/// explorer at `/docs`.
library;

import 'dart:io';

/// A minimal JSON Schema builder for request/response payloads.
///
/// Covers the common shapes without pulling in a schema package; use
/// [ApiSchema.raw] for anything it doesn't model.
///
/// ```dart
/// final userSchema = ApiSchema.object(
///   properties: {
///     'id': ApiSchema.integer(),
///     'name': ApiSchema.string(),
///     'roles': ApiSchema.array(ApiSchema.string()),
///   },
///   required: ['name'],
/// );
/// ```
class ApiSchema {
  /// An object schema with named [properties]; [required] lists the property
  /// names that must be present.
  ApiSchema.object({
    Map<String, ApiSchema> properties = const {},
    List<String> required = const [],
    String? description,
  }) : _json = {
          'type': 'object',
          if (properties.isNotEmpty)
            'properties':
                properties.map((name, s) => MapEntry(name, s.toJson())),
          if (required.isNotEmpty) 'required': required,
          if (description != null) 'description': description,
        };

  /// A string schema; [enumValues] restricts it to a fixed set and [format]
  /// is a standard OpenAPI format hint (`date-time`, `email`, `uuid`, ...).
  ApiSchema.string({
    String? format,
    List<String>? enumValues,
    String? description,
    Object? example,
  }) : _json = {
          'type': 'string',
          if (format != null) 'format': format,
          if (enumValues != null) 'enum': enumValues,
          if (description != null) 'description': description,
          if (example != null) 'example': example,
        };

  /// An integer schema.
  ApiSchema.integer({String? description, Object? example})
      : _json = {
          'type': 'integer',
          if (description != null) 'description': description,
          if (example != null) 'example': example,
        };

  /// A number (double) schema.
  ApiSchema.number({String? description, Object? example})
      : _json = {
          'type': 'number',
          if (description != null) 'description': description,
          if (example != null) 'example': example,
        };

  /// A boolean schema.
  ApiSchema.boolean({String? description})
      : _json = {
          'type': 'boolean',
          if (description != null) 'description': description,
        };

  /// An array schema whose elements match [items].
  ApiSchema.array(ApiSchema items, {String? description})
      : _json = {
          'type': 'array',
          'items': items.toJson(),
          if (description != null) 'description': description,
        };

  /// An escape hatch: any raw OpenAPI schema fragment.
  ApiSchema.raw(Map<String, dynamic> json) : _json = Map.of(json);

  final Map<String, dynamic> _json;

  /// The schema as an OpenAPI JSON fragment.
  Map<String, dynamic> toJson() => Map.unmodifiable(_json);
}

/// An authentication scheme for the generated documentation.
///
/// Declare schemes on `useOpenApi(securitySchemes: ...)` and reference them
/// per route with `ApiDoc(security: ['name'])` — the docs UI then shows an
/// Authorize button and sends the credential with try-it-out requests:
///
/// ```dart
/// app.useOpenApi(
///   securitySchemes: {
///     'apiKey': ApiSecurityScheme.apiKey('x-api-key'),
///     'bearer': ApiSecurityScheme.bearer(),
///   },
/// );
///
/// routes.post('/', store, doc: ApiDoc(security: ['apiKey'], ...));
/// ```
class ApiSecurityScheme {
  /// An API key sent with each request. [name] is the header/query/cookie
  /// name; [location] is `header` (default), `query` or `cookie`.
  ApiSecurityScheme.apiKey(
    String name, {
    String location = 'header',
    String? description,
  }) : _json = {
          'type': 'apiKey',
          'name': name,
          'in': location,
          if (description != null) 'description': description,
        };

  /// HTTP Bearer authentication (`Authorization: Bearer <token>` — commonly
  /// a JWT, which [bearerFormat] can note).
  ApiSecurityScheme.bearer({String? bearerFormat, String? description})
      : _json = {
          'type': 'http',
          'scheme': 'bearer',
          if (bearerFormat != null) 'bearerFormat': bearerFormat,
          if (description != null) 'description': description,
        };

  /// HTTP Basic authentication.
  ApiSecurityScheme.basic({String? description})
      : _json = {
          'type': 'http',
          'scheme': 'basic',
          if (description != null) 'description': description,
        };

  /// An escape hatch: any raw OpenAPI Security Scheme Object (e.g. `oauth2`
  /// or `openIdConnect` flows).
  ApiSecurityScheme.raw(Map<String, dynamic> json) : _json = Map.of(json);

  final Map<String, dynamic> _json;

  /// The scheme as an OpenAPI JSON fragment.
  Map<String, dynamic> toJson() => Map.unmodifiable(_json);
}

/// Documentation for a single path or query parameter.
class ApiParam {
  /// Creates parameter docs; [required] only applies to query parameters
  /// (path parameters are always required).
  const ApiParam({
    this.description,
    this.schema,
    this.required = false,
    this.example,
  });

  /// Human-readable description shown in the docs UI.
  final String? description;

  /// The parameter's schema; defaults to a plain string.
  final ApiSchema? schema;

  /// Whether a query parameter must be supplied.
  final bool required;

  /// An example value.
  final Object? example;
}

/// Documentation for a request body.
class ApiBody {
  /// Creates request-body docs for the given [schema].
  const ApiBody({
    this.schema,
    this.description,
    this.required = true,
    this.contentType = 'application/json',
  });

  /// The body schema.
  final ApiSchema? schema;

  /// Human-readable description.
  final String? description;

  /// Whether the body must be supplied.
  final bool required;

  /// The media type the body is documented under.
  final String contentType;
}

/// Documentation for one response status.
class ApiResponse {
  /// Creates response docs; [description] is required by the OpenAPI spec.
  const ApiResponse(
    this.description, {
    this.schema,
    this.contentType = 'application/json',
  });

  /// What this response means.
  final String description;

  /// The response body schema, if any.
  final ApiSchema? schema;

  /// The media type the schema is documented under.
  final String contentType;
}

/// Rich documentation for a route, attached via the `doc:` argument on
/// route registration (both the controller `RouteRegistrar` verbs and the
/// `DartServer` verbs accept it).
///
/// Everything is optional — undocumented routes still appear in the
/// specification with their method, path and path parameters inferred.
class ApiDoc {
  /// Creates route documentation.
  const ApiDoc({
    this.summary,
    this.description,
    this.tags,
    this.params,
    this.body,
    this.responses,
    this.security,
    this.deprecated = false,
    this.hidden = false,
  });

  /// One-line summary shown in the operation list.
  final String? summary;

  /// Longer description (CommonMark).
  final String? description;

  /// Grouping tags; defaults to the first path segment when omitted.
  final List<String>? tags;

  /// Per-parameter docs, keyed by name. Names matching a `:param` in the
  /// path document that path parameter; any other name documents a query
  /// parameter.
  final Map<String, ApiParam>? params;

  /// Request body documentation.
  final ApiBody? body;

  /// Response documentation keyed by status code. Defaults to a bare `200`.
  final Map<int, ApiResponse>? responses;

  /// Names of security schemes (from `useOpenApi(securitySchemes: ...)`)
  /// that protect this route.
  final List<String>? security;

  /// Marks the operation as deprecated in the docs.
  final bool deprecated;

  /// Excludes the route from the specification entirely.
  final bool hidden;
}

/// A route as the generator sees it: HTTP method, path pattern and optional
/// [ApiDoc] metadata.
typedef DocumentedRoute = ({String method, String pattern, ApiDoc? doc});

/// Builds an OpenAPI 3.0 specification from a route table.
///
/// Used by `DartServer.useOpenApi`; you normally don't call this directly.
class OpenApiGenerator {
  OpenApiGenerator._();

  /// Generates the specification document.
  ///
  /// Routes under [excludePaths] prefixes, routes marked `hidden: true` and
  /// `ALL`-method routes are skipped ("matches any method" has no OpenAPI
  /// representation).
  static Map<String, dynamic> generate({
    required List<DocumentedRoute> routes,
    required String title,
    required String version,
    String? description,
    List<String> servers = const [],
    Map<String, ApiSecurityScheme> securitySchemes = const {},
    List<String> excludePaths = const [],
  }) {
    final paths = <String, Map<String, dynamic>>{};
    // First-seen template per name-agnostic hierarchy: /users/:id [GET] and
    // /users/:userId [PUT] must merge into ONE path item — the OpenAPI spec
    // forbids sibling templated paths that differ only in parameter names.
    final canonicalTemplates = <String, (String, List<String>)>{};

    for (final route in routes) {
      final method = route.method.toLowerCase();
      if (method == 'all') continue;
      if (route.doc?.hidden ?? false) continue;
      if (excludePaths.any((prefix) =>
          route.pattern == prefix || route.pattern.startsWith('$prefix/'))) {
        continue;
      }

      var (openApiPath, pathParams) = _convertPath(route.pattern);
      final normalized = openApiPath.replaceAll(_templateExpression, '{}');
      final canonical = canonicalTemplates[normalized];
      var emittedParams = pathParams;
      if (canonical == null) {
        canonicalTemplates[normalized] = (openApiPath, pathParams);
      } else {
        // Reuse the first-seen path and parameter names for this hierarchy.
        openApiPath = canonical.$1;
        emittedParams = canonical.$2;
      }

      // Surface dangling security references instead of emitting an invalid
      // document silently.
      for (final scheme in route.doc?.security ?? const <String>[]) {
        if (!securitySchemes.containsKey(scheme)) {
          stderr.writeln(
              "OpenAPI: route '${route.method} ${route.pattern}' references "
              "security scheme '$scheme', which is not declared in "
              'useOpenApi(securitySchemes: ...).');
        }
      }

      final operation = _operation(route, openApiPath,
          declaredParams: pathParams, emittedParams: emittedParams);
      // First registration wins, mirroring the router's matching order.
      paths
          .putIfAbsent(openApiPath, () => {})
          .putIfAbsent(method, () => operation);
    }

    return {
      'openapi': '3.0.3',
      'info': {
        'title': title,
        'version': version,
        if (description != null) 'description': description,
      },
      if (servers.isNotEmpty)
        'servers': [
          for (final url in servers) {'url': url}
        ],
      'paths': paths,
      if (securitySchemes.isNotEmpty)
        'components': {
          'securitySchemes': securitySchemes
              .map((name, scheme) => MapEntry(name, scheme.toJson())),
        },
    };
  }

  /// Matches one `{name}` template expression in an OpenAPI path.
  static final _templateExpression = RegExp(r'\{[^}]*\}');

  /// Converts a router pattern to an OpenAPI path and collects its parameter
  /// names: `/users/:id` becomes `/users/{id}`, and a trailing wildcard `*`
  /// becomes a `{path}` parameter (renamed `path2`, `path3`, ... if the route
  /// already has a parameter with that name).
  static (String, List<String>) _convertPath(String pattern) {
    final params = <String>[];
    final segments = pattern.split('/').map((segment) {
      if (segment.startsWith(':')) {
        final name = segment.substring(1);
        params.add(name);
        return '{$name}';
      }
      if (segment == '*') {
        var name = 'path';
        var suffix = 1;
        while (params.contains(name)) {
          name = 'path${++suffix}';
        }
        params.add(name);
        return '{$name}';
      }
      return segment;
    });
    return (segments.join('/'), params);
  }

  /// Builds one Operation Object. [declaredParams] are the parameter names as
  /// written on this route; [emittedParams] are the (possibly canonicalized)
  /// names that appear in the emitted path template — same order and length.
  static Map<String, dynamic> _operation(
    DocumentedRoute route,
    String openApiPath, {
    required List<String> declaredParams,
    required List<String> emittedParams,
  }) {
    final doc = route.doc;
    final docParams = doc?.params ?? const <String, ApiParam>{};

    final parameters = <Map<String, dynamic>>[
      for (var i = 0; i < emittedParams.length; i++)
        _parameter(emittedParams[i], 'path', docParams[declaredParams[i]],
            requiredOverride: true),
      for (final entry in docParams.entries)
        if (!declaredParams.contains(entry.key))
          _parameter(entry.key, 'query', entry.value),
    ];

    final responses = <String, dynamic>{};
    final docResponses = doc?.responses;
    if (docResponses == null || docResponses.isEmpty) {
      responses['200'] = {'description': 'Success'};
    } else {
      docResponses.forEach((status, response) {
        responses['$status'] = {
          'description': response.description,
          if (response.schema != null)
            'content': {
              response.contentType: {'schema': response.schema!.toJson()},
            },
        };
      });
    }

    final body = doc?.body;

    return {
      if (doc?.summary != null) 'summary': doc!.summary,
      if (doc?.description != null) 'description': doc!.description,
      'tags': doc?.tags ?? [_defaultTag(openApiPath)],
      if (doc?.deprecated ?? false) 'deprecated': true,
      if (parameters.isNotEmpty) 'parameters': parameters,
      if (body != null)
        'requestBody': {
          if (body.description != null) 'description': body.description,
          'required': body.required,
          'content': {
            body.contentType: {
              if (body.schema != null) 'schema': body.schema!.toJson(),
            },
          },
        },
      'responses': responses,
      if (doc?.security != null)
        'security': [
          for (final scheme in doc!.security!) {scheme: <String>[]},
        ],
    };
  }

  /// Default grouping tag for an undocumented route: its first path segment,
  /// or `default` for the root.
  static String _defaultTag(String openApiPath) {
    final segments =
        openApiPath.split('/').where((s) => s.isNotEmpty && !s.startsWith('{'));
    return segments.isEmpty ? 'default' : segments.first;
  }

  static Map<String, dynamic> _parameter(
    String name,
    String location,
    ApiParam? param, {
    bool requiredOverride = false,
  }) {
    return {
      'name': name,
      'in': location,
      'required': requiredOverride || (param?.required ?? false),
      if (param?.description != null) 'description': param!.description,
      'schema': param?.schema?.toJson() ?? {'type': 'string'},
      if (param?.example != null) 'example': param!.example,
    };
  }
}

/// The interactive documentation page. `__SPEC_URL__` and `__TITLE__` are
/// substituted at render time. The explorer assets load from a CDN, so the
/// page needs internet access; the JSON specification itself is always
/// served locally.
const String swaggerUiTemplate = '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>__TITLE__ · API docs</title>
  <link rel="stylesheet"
        href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
  <style>body { margin: 0; }</style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({
      url: '__SPEC_URL__',
      dom_id: '#swagger-ui',
      deepLinking: true,
      presets: [SwaggerUIBundle.presets.apis],
      layout: 'BaseLayout',
    });
  </script>
</body>
</html>''';
