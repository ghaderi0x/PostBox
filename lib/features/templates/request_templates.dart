import 'dart:convert';

import '../../core/model/key_value.dart';
import '../../core/util/ids.dart';
import '../../core/util/json_util.dart';
import '../persistence/app_database.dart';
import '../requests/domain/request_models.dart';

/// A reusable starting point for new requests.
class RequestTemplate {
  const RequestTemplate({
    required this.id,
    required this.name,
    required this.request,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final RequestModel request;
  final bool builtIn;

  /// A fresh request (new id) based on this template.
  RequestModel instantiate() => request.copyWith(id: newId());
}

/// Templates shipped with the app. They contain no secrets and no real hosts.
List<RequestTemplate> builtInTemplates() => <RequestTemplate>[
  RequestTemplate(
    id: 'builtin.get-json',
    name: 'GET JSON',
    builtIn: true,
    request: RequestModel(
      id: 'tpl',
      name: 'GET JSON',
      url: '{{base_url}}/items',
      headers: const <KeyValue>[
        KeyValue(key: 'Accept', value: 'application/json'),
      ],
    ),
  ),
  RequestTemplate(
    id: 'builtin.post-json',
    name: 'POST JSON',
    builtIn: true,
    request: RequestModel(
      id: 'tpl',
      name: 'POST JSON',
      method: 'POST',
      url: '{{base_url}}/items',
      bodyType: BodyType.json,
      body: '{\n  "name": "example"\n}',
    ),
  ),
  RequestTemplate(
    id: 'builtin.bearer-get',
    name: 'GET with Bearer token',
    builtIn: true,
    request: RequestModel(
      id: 'tpl',
      name: 'GET with Bearer token',
      url: '{{base_url}}/me',
      auth: const AuthConfig(type: AuthType.bearer),
    ),
  ),
  RequestTemplate(
    id: 'builtin.form-login',
    name: 'Form login',
    builtIn: true,
    request: RequestModel(
      id: 'tpl',
      name: 'Form login',
      method: 'POST',
      url: '{{base_url}}/login',
      bodyType: BodyType.formUrlEncoded,
      formFields: const <KeyValue>[
        KeyValue(key: 'username', value: '{{username}}'),
        KeyValue(key: 'password', value: '{{password}}'),
      ],
    ),
  ),
  RequestTemplate(
    id: 'builtin.graphql',
    name: 'GraphQL query',
    builtIn: true,
    request: RequestModel(
      id: 'tpl',
      name: 'GraphQL query',
      method: 'POST',
      url: '{{base_url}}/graphql',
      bodyType: BodyType.graphql,
      body: '{\n  __typename\n}',
    ),
  ),
];

/// User templates, stored in the `templates` table. Secrets are never stored:
/// auth values are blanked when a template is saved.
class TemplateStore {
  TemplateStore(this._app);

  final AppDatabase _app;

  List<RequestTemplate> list() =>
      _app.db.select('SELECT * FROM templates ORDER BY created DESC').map((r) {
        RequestModel req;
        try {
          req = RequestModel.fromJson(jsonDecode(r['data_json'] as String));
        } on FormatException {
          req = RequestModel(id: 'tpl');
        }
        return RequestTemplate(
          id: r['id'] as String,
          name: r['name'] as String,
          request: req,
        );
      }).toList();

  RequestTemplate add(String name, RequestModel request) {
    final clean = request.copyWith(
      auth: request.auth.withoutSecrets(),
      name: name,
    );
    final id = newId();
    _app.db.execute(
      'INSERT INTO templates(id,name,data_json,created) VALUES(?,?,?,?)',
      <Object?>[
        id,
        name,
        jsonEncode(clean.toJson()),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return RequestTemplate(id: id, name: name, request: clean);
  }

  void delete(String id) {
    _app.db.execute('DELETE FROM templates WHERE id=?', <Object?>[id]);
  }

  int count() => asInt(
    _app.db.select('SELECT COUNT(*) AS n FROM templates').first['n'],
    0,
  );
}
