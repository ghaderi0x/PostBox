import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/collections/domain/collection_models.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/import_export/openapi.dart';
import 'package:postbox/features/import_export/postbox_format.dart';
import 'package:postbox/features/import_export/postman.dart';
import 'package:postbox/features/requests/domain/request_models.dart';

const String _postman = '''
{
  "info": {"name": "Demo", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
  "variable": [{"key": "base", "value": "https://api.test"}, {"key": "api_token", "value": "t"}],
  "item": [
    {"name": "Users", "item": [
      {"name": "List", "request": {
        "method": "GET",
        "header": [{"key": "Accept", "value": "application/json"}, {"key": "X-Off", "value": "1", "disabled": true}],
        "url": {"raw": "{{base}}/users?page=1", "query": [{"key": "page", "value": "1"}]},
        "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "abc"}]}
      }, "event": [{"listen": "test", "script": {"exec": ["pm.test('x')"]}}]},
      {"name": "Create", "request": {
        "method": "POST",
        "url": "{{base}}/users",
        "body": {"mode": "raw", "raw": "{\\"a\\":1}", "options": {"raw": {"language": "json"}}}
      }}
    ]},
    {"name": "Upload", "request": {
      "method": "POST", "url": {"raw": "{{base}}/up"},
      "body": {"mode": "formdata", "formdata": [{"key": "f", "type": "file", "src": "/tmp/x"}, {"key": "t", "type": "text", "value": "v"}]},
      "auth": {"type": "oauth2"}
    }}
  ]
}
''';

void main() {
  group('Postman import', () {
    final plan = parsePostmanCollection(_postman);
    final col = plan.collections.single;

    test('structure', () {
      expect(plan.hasErrors, isFalse);
      expect(col.name, 'Demo');
      expect(col.requestCount, 3);
      expect(col.nodes.first.isFolder, isTrue);
      expect(col.nodes.first.name, 'Users');
      expect(col.variables.map((v) => v.key), <String>['base', 'api_token']);
    });

    test('request details', () {
      final list = col.nodes.first.children.first.request!;
      expect(list.url, '{{base}}/users');
      expect(list.params.single.key, 'page');
      expect(list.headers.length, 2);
      expect(list.headers[1].enabled, isFalse);
      expect(list.auth.type, AuthType.bearer);
      expect(list.auth.token, 'abc');
      final create = col.nodes.first.children[1].request!;
      expect(create.bodyType, BodyType.json);
      expect(create.body, '{"a":1}');
      final up = col.nodes[1].request!;
      expect(up.bodyType, BodyType.multipart);
      expect(up.formFields[0].isFile, isTrue);
      expect(up.auth.type, AuthType.none);
    });

    test('scripts and unsupported auth are reported, never run', () {
      final msgs = plan.notes.map((n) => n.message).join('\n');
      expect(msgs, contains('script'));
      expect(msgs, contains('unsupported auth'));
      expect(msgs.toLowerCase(), contains('secret'));
    });

    test('rejects malformed input', () {
      expect(parsePostmanCollection('{').hasErrors, isTrue);
      expect(parsePostmanCollection('[]').hasErrors, isTrue);
      expect(parsePostmanCollection('{"info":{"name":"x","schema":"foo"},"item":[]}').hasErrors, isTrue);
      expect(parsePostmanCollection('{"nothing":1}').hasErrors, isTrue);
      expect(parsePostmanCollection('x' * (11 * 1024 * 1024)).hasErrors, isTrue);
    });
  });

  group('Postman export', () {
    final col = ImportedCollection(
      name: 'Exp',
      variables: <Variable>[
        const Variable(id: '1', key: 'k', value: 'public'),
        const Variable(id: '2', key: 's', value: 'hidden', secret: true),
      ],
      nodes: <ImportedNode>[
        ImportedNode.request(const RequestModel(
          id: 'r',
          name: 'One',
          method: 'POST',
          url: 'https://a.test/x',
          bodyType: BodyType.json,
          body: '{"a":1}',
          auth: AuthConfig(type: AuthType.bearer, token: 'SECRETTOKEN'),
        )),
      ],
    );

    test('omits secrets by default', () {
      final text = jsonEncode(exportPostmanCollection(col));
      expect(text.contains('SECRETTOKEN'), isFalse);
      expect(text.contains('hidden'), isFalse);
      expect(text, contains('collection/v2.1.0'));
    });

    test('includes secrets when asked', () {
      final text = jsonEncode(exportPostmanCollection(col, includeSecrets: true));
      expect(text, contains('SECRETTOKEN'));
      expect(text, contains('hidden'));
    });

    test('export then import keeps requests', () {
      final text = prettyJson(exportPostmanCollection(col, includeSecrets: true));
      final back = parsePostmanCollection(text);
      expect(back.hasErrors, isFalse);
      final r = back.collections.single.nodes.single.request!;
      expect(r.method, 'POST');
      expect(r.url, 'https://a.test/x');
      expect(r.bodyType, BodyType.json);
      expect(r.auth.token, 'SECRETTOKEN');
    });
  });

  group('PostBox format', () {
    final col = ImportedCollection(
      name: 'Mine',
      description: 'desc',
      variables: <Variable>[const Variable(id: 'v', key: 'sec', value: 'topsecret', secret: true)],
      nodes: <ImportedNode>[
        ImportedNode.folder('F', <ImportedNode>[
          ImportedNode.request(const RequestModel(
            id: 'r1',
            name: 'Req',
            url: 'https://a.test',
            auth: AuthConfig(type: AuthType.basic, username: 'u', password: 'PASSWORD'),
          )),
        ]),
      ],
    );
    final envs = <Environment>[
      const Environment(id: 'e', name: 'Prod', variables: <Variable>[Variable(id: 'x', key: 'k', value: 'v')]),
    ];

    test('default export has no secrets and re-imports', () {
      final map = exportPostBox(collections: <ImportedCollection>[col], environments: envs);
      final text = jsonEncode(map);
      expect(text.contains('PASSWORD'), isFalse);
      expect(text.contains('topsecret'), isFalse);
      expect(map['format'], 'postbox');
      expect(map['version'], 1);
      final plan = parsePostBox(text);
      expect(plan.hasErrors, isFalse);
      expect(plan.collections.single.name, 'Mine');
      expect(plan.collections.single.requestCount, 1);
      expect(plan.environments.single.name, 'Prod');
      expect(plan.notes.any((n) => n.message.contains('no secrets')), isTrue);
    });

    test('import assigns fresh ids', () {
      final text = jsonEncode(exportPostBox(collections: <ImportedCollection>[col]));
      final r = parsePostBox(text).collections.single.nodes.single.children.single.request!;
      expect(r.id, isNot('r1'));
    });

    test('opt-in export carries secrets', () {
      final text = jsonEncode(exportPostBox(collections: <ImportedCollection>[col], includeSecrets: true));
      expect(text, contains('PASSWORD'));
      expect(text, contains('topsecret'));
    });

    test('rejects other formats and future versions', () {
      expect(parsePostBox('{"format":"other"}').hasErrors, isTrue);
      expect(parsePostBox('{"format":"postbox","version":99}').hasErrors, isTrue);
      expect(parsePostBox('nope').hasErrors, isTrue);
    });
  });

  group('OpenAPI import', () {
    const doc = '''
{
  "openapi": "3.0.3",
  "info": {"title": "Pets", "description": "Pet store"},
  "servers": [{"url": "https://pets.test/v1"}],
  "paths": {
    "/pets/{petId}": {
      "get": {"summary": "Get pet", "tags": ["pets"],
        "parameters": [
          {"name": "petId", "in": "path", "required": true, "schema": {"type": "string"}},
          {"name": "verbose", "in": "query", "schema": {"type": "boolean"}}
        ]},
      "put": {"operationId": "updatePet", "tags": ["pets"],
        "requestBody": {"content": {"application/json": {"schema": {"\$ref": "#/components/schemas/Pet"}}}}}
    },
    "/health": {"get": {}}
  },
  "components": {"schemas": {"Pet": {"type": "object", "properties": {"name": {"type": "string"}, "age": {"type": "integer"}}}},
    "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}}}
}
''';

    test('creates folders, requests, variables', () {
      final plan = parseOpenApi(doc);
      expect(plan.hasErrors, isFalse);
      final c = plan.collections.single;
      expect(c.name, 'Pets');
      expect(c.requestCount, 3);
      expect(c.variables.firstWhere((v) => v.key == 'base_url').value, 'https://pets.test/v1');
      expect(c.variables.any((v) => v.key == 'petId'), isTrue);
      final folder = c.nodes.firstWhere((n) => n.isFolder);
      expect(folder.name, 'pets');
      final get = folder.children.first.request!;
      expect(get.url, '{{base_url}}/pets/{{petId}}');
      expect(get.params.single.key, 'verbose');
      expect(get.params.single.enabled, isFalse);
      final put = folder.children[1].request!;
      expect(put.bodyType, BodyType.json);
      expect(jsonDecode(put.body), <String, dynamic>{'name': 'string', 'age': 0});
      expect(plan.notes.any((n) => n.message.contains('Security schemes')), isTrue);
    });

    test('rejects non-OpenAPI 3 input', () {
      expect(parseOpenApi('{"swagger":"2.0"}').hasErrors, isTrue);
      expect(parseOpenApi('openapi: 3.0.0').hasErrors, isTrue);
      expect(parseOpenApi('{"openapi":"3.0.0","paths":{}}').hasErrors, isTrue);
    });
  });
}
