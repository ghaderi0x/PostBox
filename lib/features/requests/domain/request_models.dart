import 'dart:convert';

import '../../../core/model/key_value.dart';
import '../../../core/util/ids.dart';
import '../../../core/util/json_util.dart';
import '../../testing/domain/assertions.dart';

enum RequestKind { http, sse, websocket }

/// `binary` sends one file from disk ([RequestModel.body] holds its path).
enum BodyType {
  none,
  json,
  text,
  formUrlEncoded,
  multipart,
  raw,
  graphql,
  binary,
}

/// `inherit` uses the auth of the nearest folder or collection that defines
/// one (see InheritanceResolver). It is never sent on the wire by itself.
enum AuthType { none, basic, bearer, apiKey, oauth2, inherit }

/// Authentication settings. Fields listed in [secretFields] are persisted in
/// secure storage, never in the database or exports (unless opted in).
class AuthConfig {
  const AuthConfig({
    this.type = AuthType.none,
    this.username = '',
    this.password = '',
    this.token = '',
    this.apiKeyName = 'X-API-Key',
    this.apiKeyValue = '',
    this.apiKeyInHeader = true,
    this.authUrl = '',
    this.tokenUrl = '',
    this.clientId = '',
    this.clientSecret = '',
    this.scope = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.expiresAtMs = 0,
  });

  final AuthType type;
  final String username;
  final String password;
  final String token;
  final String apiKeyName;
  final String apiKeyValue;
  final bool apiKeyInHeader;
  final String authUrl;
  final String tokenUrl;
  final String clientId;
  final String clientSecret;
  final String scope;
  final String accessToken;
  final String refreshToken;

  /// Epoch milliseconds, 0 when unknown.
  final int expiresAtMs;

  static const List<String> secretKeys = <String>[
    'password',
    'token',
    'apiKeyValue',
    'clientSecret',
    'accessToken',
    'refreshToken',
  ];

  Map<String, String> secretFields() => <String, String>{
    'password': password,
    'token': token,
    'apiKeyValue': apiKeyValue,
    'clientSecret': clientSecret,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };

  AuthConfig withSecrets(Map<String, String> s) => copyWith(
    password: s['password'],
    token: s['token'],
    apiKeyValue: s['apiKeyValue'],
    clientSecret: s['clientSecret'],
    accessToken: s['accessToken'],
    refreshToken: s['refreshToken'],
  );

  AuthConfig withoutSecrets() => AuthConfig(
    type: type,
    username: username,
    apiKeyName: apiKeyName,
    apiKeyInHeader: apiKeyInHeader,
    authUrl: authUrl,
    tokenUrl: tokenUrl,
    clientId: clientId,
    scope: scope,
    expiresAtMs: expiresAtMs,
  );

  AuthConfig copyWith({
    AuthType? type,
    String? username,
    String? password,
    String? token,
    String? apiKeyName,
    String? apiKeyValue,
    bool? apiKeyInHeader,
    String? authUrl,
    String? tokenUrl,
    String? clientId,
    String? clientSecret,
    String? scope,
    String? accessToken,
    String? refreshToken,
    int? expiresAtMs,
  }) => AuthConfig(
    type: type ?? this.type,
    username: username ?? this.username,
    password: password ?? this.password,
    token: token ?? this.token,
    apiKeyName: apiKeyName ?? this.apiKeyName,
    apiKeyValue: apiKeyValue ?? this.apiKeyValue,
    apiKeyInHeader: apiKeyInHeader ?? this.apiKeyInHeader,
    authUrl: authUrl ?? this.authUrl,
    tokenUrl: tokenUrl ?? this.tokenUrl,
    clientId: clientId ?? this.clientId,
    clientSecret: clientSecret ?? this.clientSecret,
    scope: scope ?? this.scope,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
  );

  Map<String, dynamic> toJson({bool includeSecrets = false}) =>
      <String, dynamic>{
        'type': type.name,
        'username': username,
        'apiKeyName': apiKeyName,
        'apiKeyInHeader': apiKeyInHeader,
        'authUrl': authUrl,
        'tokenUrl': tokenUrl,
        'clientId': clientId,
        'scope': scope,
        'expiresAtMs': expiresAtMs,
        if (includeSecrets) ...secretFields(),
      };

  factory AuthConfig.fromJson(Object? j) {
    final m = asMap(j);
    return AuthConfig(
      type: enumByName(AuthType.values, m['type'], AuthType.none),
      username: asString(m['username']),
      password: asString(m['password']),
      token: asString(m['token']),
      apiKeyName: asString(m['apiKeyName'], 'X-API-Key'),
      apiKeyValue: asString(m['apiKeyValue']),
      apiKeyInHeader: asBool(m['apiKeyInHeader'], true),
      authUrl: asString(m['authUrl']),
      tokenUrl: asString(m['tokenUrl']),
      clientId: asString(m['clientId']),
      clientSecret: asString(m['clientSecret']),
      scope: asString(m['scope']),
      accessToken: asString(m['accessToken']),
      refreshToken: asString(m['refreshToken']),
      expiresAtMs: asInt(m['expiresAtMs'], 0),
    );
  }
}

class RequestModel {
  const RequestModel({
    required this.id,
    this.name = '',
    this.kind = RequestKind.http,
    this.method = 'GET',
    this.url = '',
    this.params = const <KeyValue>[],
    this.headers = const <KeyValue>[],
    this.bodyType = BodyType.none,
    this.body = '',
    this.bodyAux = '',
    this.formFields = const <KeyValue>[],
    this.auth = const AuthConfig(),
    this.description = '',
    this.assertions = const <Assertion>[],
    this.extractions = const <Extraction>[],
    this.variables = const <KeyValue>[],
    this.preScript = '',
    this.postScript = '',
  });

  final String id;
  final String name;
  final RequestKind kind;
  final String method;
  final String url;
  final List<KeyValue> params;
  final List<KeyValue> headers;
  final BodyType bodyType;

  /// JSON/text/raw content, or the GraphQL query.
  final String body;

  /// GraphQL variables (JSON text) or the raw body's Content-Type.
  final String bodyAux;

  /// Rows for form-urlencoded and multipart bodies.
  final List<KeyValue> formFields;
  final AuthConfig auth;
  final String description;
  final List<Assertion> assertions;
  final List<Extraction> extractions;

  /// Request-level variables (plain text, never secret). They override folder
  /// and collection variables but not the active environment.
  final List<KeyValue> variables;

  /// Sandboxed scripts (see features/scripting). Empty means none.
  final String preScript;
  final String postScript;

  factory RequestModel.blank({
    String method = 'GET',
    RequestKind kind = RequestKind.http,
  }) => RequestModel(id: newId(), method: method, kind: kind);

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (url.trim().isNotEmpty) return url.trim();
    return '';
  }

  RequestModel copyWith({
    String? id,
    String? name,
    RequestKind? kind,
    String? method,
    String? url,
    List<KeyValue>? params,
    List<KeyValue>? headers,
    BodyType? bodyType,
    String? body,
    String? bodyAux,
    List<KeyValue>? formFields,
    AuthConfig? auth,
    String? description,
    List<Assertion>? assertions,
    List<Extraction>? extractions,
    List<KeyValue>? variables,
    String? preScript,
    String? postScript,
  }) => RequestModel(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    method: method ?? this.method,
    url: url ?? this.url,
    params: params ?? this.params,
    headers: headers ?? this.headers,
    bodyType: bodyType ?? this.bodyType,
    body: body ?? this.body,
    bodyAux: bodyAux ?? this.bodyAux,
    formFields: formFields ?? this.formFields,
    auth: auth ?? this.auth,
    description: description ?? this.description,
    assertions: assertions ?? this.assertions,
    extractions: extractions ?? this.extractions,
    variables: variables ?? this.variables,
    preScript: preScript ?? this.preScript,
    postScript: postScript ?? this.postScript,
  );

  Map<String, dynamic> toJson({bool includeSecrets = false}) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'method': method,
        'url': url,
        'params': KeyValue.listToJson(params),
        'headers': KeyValue.listToJson(headers),
        'bodyType': bodyType.name,
        'body': body,
        'bodyAux': bodyAux,
        'formFields': KeyValue.listToJson(formFields),
        'auth': auth.toJson(includeSecrets: includeSecrets),
        'description': description,
        'assertions': assertions.map((a) => a.toJson()).toList(),
        'extractions': extractions.map((e) => e.toJson()).toList(),
        'variables': KeyValue.listToJson(variables),
        if (preScript.isNotEmpty) 'preScript': preScript,
        if (postScript.isNotEmpty) 'postScript': postScript,
      };

  /// Stable string used for dirty-state comparison.
  String fingerprint() => jsonEncode(toJson(includeSecrets: true));

  factory RequestModel.fromJson(Object? j) {
    final m = asMap(j);
    return RequestModel(
      id: asString(m['id']).isEmpty ? newId() : asString(m['id']),
      name: asString(m['name']),
      kind: enumByName(RequestKind.values, m['kind'], RequestKind.http),
      method: asString(m['method'], 'GET'),
      url: asString(m['url']),
      params: KeyValue.listFromJson(m['params']),
      headers: KeyValue.listFromJson(m['headers']),
      bodyType: enumByName(BodyType.values, m['bodyType'], BodyType.none),
      body: asString(m['body']),
      bodyAux: asString(m['bodyAux']),
      formFields: KeyValue.listFromJson(m['formFields']),
      auth: AuthConfig.fromJson(m['auth']),
      description: asString(m['description']),
      assertions: asList(m['assertions']).map(Assertion.fromJson).toList(),
      extractions: asList(m['extractions']).map(Extraction.fromJson).toList(),
      variables: KeyValue.listFromJson(m['variables']),
      preScript: asString(m['preScript']),
      postScript: asString(m['postScript']),
    );
  }
}

/// Splits `https://x/y?a=1&b=2` into the base URL and decoded parameter rows.
(String, List<KeyValue>) splitUrlQuery(String url) {
  final hash = url.indexOf('#');
  final noHash = hash >= 0 ? url.substring(0, hash) : url;
  final q = noHash.indexOf('?');
  if (q < 0) return (noHash, const <KeyValue>[]);
  final base = noHash.substring(0, q);
  final params = <KeyValue>[];
  for (final part in noHash.substring(q + 1).split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    String dec(String s) {
      try {
        return Uri.decodeQueryComponent(s);
      } on ArgumentError {
        return s;
      }
    }

    params.add(
      eq < 0
          ? KeyValue(key: dec(part))
          : KeyValue(
              key: dec(part.substring(0, eq)),
              value: dec(part.substring(eq + 1)),
            ),
    );
  }
  return (base, params);
}
