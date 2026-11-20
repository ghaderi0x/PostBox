import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/collections/domain/collection_models.dart';
import 'package:postbox/features/collections/domain/node_settings.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/import_export/curl.dart';
import 'package:postbox/features/import_export/postbox_format.dart';
import 'package:postbox/features/import_export/postman.dart';
import 'package:postbox/features/requests/domain/request_models.dart';

Variable _v(String k, String v, {bool secret = false}) =>
    Variable(id: 'id-$k', key: k, value: v, secret: secret);

void main() {
  group('variable layers', () {
    test(
      'precedence: global < collection < folder < request < environment < runtime',
      () {
        final r = VariableResolver(
          global: <Variable>[_v('x', 'global')],
          collection: <Variable>[_v('x', 'collection')],
          folder: <Variable>[_v('x', 'outer'), _v('x', 'inner')],
          request: <Variable>[_v('x', 'request')],
          environment: <Variable>[_v('x', 'env')],
          overlay: const <String, String>{'x': 'runtime'},
        );
        expect(r.resolve('{{x}}').text, 'runtime');
        expect(r.sourceOf('x'), VariableSource.runtime);

        final noOverlay = VariableResolver(
          global: <Variable>[_v('x', 'global')],
          collection: <Variable>[_v('x', 'collection')],
          folder: <Variable>[_v('x', 'outer'), _v('x', 'inner')],
          request: <Variable>[_v('x', 'request')],
        );
        expect(noOverlay.resolve('{{x}}').text, 'request');
        expect(noOverlay.sourceOf('x'), VariableSource.request);

        final noRequest = VariableResolver(
          collection: <Variable>[_v('x', 'collection')],
          folder: <Variable>[_v('x', 'outer'), _v('x', 'inner')],
        );
        expect(noRequest.resolve('{{x}}').text, 'inner');
        expect(noRequest.sourceOf('x'), VariableSource.folder);
      },
    );

    test('the environment beats the whole collection tree', () {
      final r = VariableResolver(
        collection: <Variable>[_v('host', 'c')],
        folder: <Variable>[_v('host', 'f')],
        request: <Variable>[_v('host', 'r')],
        environment: <Variable>[_v('host', 'prod')],
      );
      expect(r.resolve('{{host}}').text, 'prod');
      expect(r.sourceOf('host'), VariableSource.environment);
    });

    test(
      'disabled variables are skipped and sources are null when undefined',
      () {
        final r = VariableResolver(
          environment: <Variable>[
            Variable(id: 'a', key: 'off', value: '1', enabled: false),
          ],
        );
        expect(r.sourceOf('off'), isNull);
        expect(r.displayValue('off'), isNull);
      },
    );

    test('secret values are masked by displayValue', () {
      final r = VariableResolver(
        environment: <Variable>[_v('tok', 'abc', secret: true)],
      );
      expect(r.displayValue('tok'), isNot('abc'));
      expect(r.isSecret('tok'), isTrue);
    });

    test('extended keeps the layers and adds new ones', () {
      final base = VariableResolver(
        collection: <Variable>[_v('a', 'c')],
        environment: <Variable>[_v('e', 'env')],
      );
      final ext = base.extended(
        folder: <Variable>[_v('a', 'folder')],
        request: <Variable>[_v('r', 'req')],
        overlay: const <String, String>{'o': 'run'},
      );
      expect(ext.resolve('{{a}} {{e}} {{r}} {{o}}').text, 'folder env req run');
      // The original is unchanged.
      expect(base.resolve('{{a}}').text, 'c');
      expect(base.sourceOf('r'), isNull);
    });
  });

  group('NodeSettings', () {
    test('JSON round trip without secrets', () {
      final s = NodeSettings(
        variables: <Variable>[_v('k', 'v'), _v('sec', 'hidden', secret: true)],
        headers: const <KeyValue>[KeyValue(key: 'X-A', value: '1')],
        auth: const AuthConfig(type: AuthType.bearer, token: 'T0K'),
        preScript: 'log("x");',
      );
      final json = jsonEncode(s.toJson());
      expect(json, isNot(contains('T0K')));
      expect(json, isNot(contains('hidden')));
      final back = NodeSettings.fromJson(jsonDecode(json));
      expect(back.auth.type, AuthType.bearer);
      expect(back.auth.token, '');
      expect(back.headers.single.key, 'X-A');
      expect(back.preScript, 'log("x");');
      expect(back.variables.length, 2);
    });

    test('with secrets included they are exported', () {
      final s = NodeSettings(
        auth: const AuthConfig(type: AuthType.bearer, token: 'T0K'),
      );
      expect(jsonEncode(s.toJson(includeSecrets: true)), contains('T0K'));
    });

    test('stripped removes secret values from variables and auth', () {
      final s = NodeSettings(
        variables: <Variable>[
          _v('sec', 'hidden', secret: true),
          _v('plain', 'ok'),
        ],
        auth: const AuthConfig(
          type: AuthType.basic,
          username: 'u',
          password: 'pw',
        ),
      ).stripped();
      expect(s.variables.first.value, '');
      expect(s.variables.last.value, 'ok');
      expect(s.auth.password, '');
      expect(s.auth.username, 'u');
    });

    test('empty and unset defaults', () {
      expect(NodeSettings.empty.isEmpty, isTrue);
      expect(NodeSettings.fromJson(null).isEmpty, isTrue);
      expect(NodeSettings.fromJson('junk').isEmpty, isTrue);
      expect(const NodeSettings().auth.type, AuthType.inherit);
      expect(
        const NodeSettings(auth: AuthConfig()).isEmpty,
        isFalse,
      ); // explicit "no auth"
    });
  });

  group('InheritanceResolver', () {
    final collection = SettingsLevel(
      'Shop API',
      NodeSettings(
        auth: const AuthConfig(
          type: AuthType.bearer,
          token: 'collection-token',
        ),
        headers: const <KeyValue>[
          KeyValue(key: 'X-Team', value: 'core'),
          KeyValue(key: 'Accept', value: 'application/json'),
        ],
        preScript: 'log("c-pre");',
        postScript: 'log("c-post");',
      ),
    );
    final folder = SettingsLevel(
      'Admin',
      NodeSettings(
        auth: const AuthConfig(
          type: AuthType.basic,
          username: 'admin',
          password: 'p',
        ),
        headers: const <KeyValue>[KeyValue(key: 'x-team', value: 'admin')],
        variables: <Variable>[_v('scope', 'admin')],
        preScript: 'log("f-pre");',
        postScript: 'log("f-post");',
      ),
    );
    final unset = SettingsLevel('Sub', NodeSettings.empty);

    test('the innermost defined auth wins; unset levels are transparent', () {
      final ctx = InheritanceResolver.resolve(<SettingsLevel>[
        collection,
        folder,
        unset,
      ]);
      expect(ctx.auth!.type, AuthType.basic);
      expect(ctx.authSource, 'Admin');
      expect(
        InheritanceResolver.resolve(<SettingsLevel>[
          collection,
          unset,
        ]).authSource,
        'Shop API',
      );
    });

    test('an explicit "no auth" stops inheritance', () {
      final none = SettingsLevel(
        'Public',
        const NodeSettings(auth: AuthConfig()),
      );
      final ctx = InheritanceResolver.resolve(<SettingsLevel>[
        collection,
        none,
      ]);
      expect(ctx.auth!.type, AuthType.none);
    });

    test('nothing defined means no auth', () {
      final ctx = InheritanceResolver.resolve(<SettingsLevel>[unset]);
      expect(ctx.auth, isNull);
      final req = InheritanceResolver.apply(
        RequestModel(
          id: 'r',
          auth: const AuthConfig(type: AuthType.inherit),
        ),
        ctx,
      );
      expect(req.auth.type, AuthType.none);
    });

    test('scripts run outermost first before and innermost first after', () {
      final ctx = InheritanceResolver.resolve(<SettingsLevel>[
        collection,
        folder,
      ]);
      expect(ctx.preScripts, <String>['log("c-pre");', 'log("f-pre");']);
      expect(ctx.postScripts, <String>['log("f-post");', 'log("c-post");']);
      expect(ctx.folderVariables.single.key, 'scope');
    });

    test('apply replaces inherited auth only', () {
      final ctx = InheritanceResolver.resolve(<SettingsLevel>[collection]);
      final inherit = InheritanceResolver.apply(
        RequestModel(
          id: 'a',
          auth: const AuthConfig(type: AuthType.inherit),
        ),
        ctx,
      );
      expect(inherit.auth.type, AuthType.bearer);
      expect(inherit.auth.token, 'collection-token');
      final own = InheritanceResolver.apply(
        RequestModel(
          id: 'b',
          auth: const AuthConfig(type: AuthType.basic),
        ),
        ctx,
      );
      expect(own.auth.type, AuthType.basic);
      final none = InheritanceResolver.apply(RequestModel(id: 'c'), ctx);
      expect(none.auth.type, AuthType.none);
    });

    test(
      'inherited headers go under the request headers, inner wins, request wins over all',
      () {
        final ctx = InheritanceResolver.resolve(<SettingsLevel>[
          collection,
          folder,
        ]);
        final req = InheritanceResolver.apply(
          RequestModel(
            id: 'r',
            headers: const <KeyValue>[
              KeyValue(key: 'ACCEPT', value: 'text/csv'),
            ],
          ),
          ctx,
        );
        final byName = <String, String>{
          for (final h in req.headers) h.key.toLowerCase(): h.value,
        };
        expect(byName['accept'], 'text/csv'); // request wins, no duplicate
        expect(
          byName['x-team'],
          'admin',
        ); // folder beats collection (case-insensitive)
        expect(
          req.headers.where((h) => h.key.toLowerCase() == 'accept').length,
          1,
        );
        expect(
          req.headers.where((h) => h.key.toLowerCase() == 'x-team').length,
          1,
        );
      },
    );

    test('disabled inherited headers are ignored', () {
      final off = SettingsLevel(
        'Off',
        const NodeSettings(
          headers: <KeyValue>[
            KeyValue(key: 'X-Off', value: '1', enabled: false),
          ],
        ),
      );
      final req = InheritanceResolver.apply(
        RequestModel(id: 'r'),
        InheritanceResolver.resolve(<SettingsLevel>[off]),
      );
      expect(req.headers, isEmpty);
    });
  });

  group('request model additions', () {
    test(
      'variables and scripts survive JSON; inherit and binary parse by name',
      () {
        final r = RequestModel(
          id: 'r',
          bodyType: BodyType.binary,
          body: '/tmp/file.bin',
          auth: const AuthConfig(type: AuthType.inherit),
          variables: const <KeyValue>[KeyValue(key: 'a', value: '1')],
          preScript: 'log(1);',
          postScript: 'log(2);',
        );
        final back = RequestModel.fromJson(jsonDecode(jsonEncode(r.toJson())));
        expect(back.bodyType, BodyType.binary);
        expect(back.auth.type, AuthType.inherit);
        expect(back.variables.single.key, 'a');
        expect(back.preScript, 'log(1);');
        expect(back.postScript, 'log(2);');
      },
    );

    test('old JSON without the new fields still loads', () {
      final r = RequestModel.fromJson(<String, dynamic>{
        'id': 'old',
        'url': 'https://x.test',
      });
      expect(r.variables, isEmpty);
      expect(r.preScript, '');
      expect(r.auth.type, AuthType.none);
    });
  });

  group('import and export of inherited settings', () {
    const postman = '''
{
  "info": {"name": "Inherit", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "col-tok"}]},
  "item": [
    {"name": "Folder", "auth": {"type": "basic", "basic": [{"key": "username", "value": "u"}, {"key": "password", "value": "p"}]},
     "variable": [{"key": "fv", "value": "1"}],
     "item": [
       {"name": "Plain", "request": {"method": "GET", "url": "https://x.test/a"}},
       {"name": "Own", "request": {"method": "GET", "url": "https://x.test/b", "auth": {"type": "noauth"}}}
     ]},
    {"name": "Top", "request": {"method": "GET", "url": "https://x.test/c"}}
  ]
}
''';

    test(
      'Postman: collection and folder auth, folder variables, inherited requests',
      () {
        final plan = parsePostmanCollection(postman);
        final col = plan.collections.single;
        expect(col.settings.auth.type, AuthType.bearer);
        expect(col.settings.auth.token, 'col-tok');
        final folder = col.nodes.first;
        expect(folder.settings.auth.type, AuthType.basic);
        expect(folder.settings.variables.single.key, 'fv');
        expect(folder.children.first.request!.auth.type, AuthType.inherit);
        expect(
          folder.children.last.request!.auth.type,
          AuthType.none,
        ); // explicit noauth
        expect(col.nodes.last.request!.auth.type, AuthType.inherit);
      },
    );

    test('Postman: a collection without any auth keeps requests at none', () {
      final plan = parsePostmanCollection(
        '{"info":{"name":"N","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"A","request":{"method":"GET","url":"https://x.test"}}]}',
      );
      expect(
        plan.collections.single.nodes.single.request!.auth.type,
        AuthType.none,
      );
    });

    test('Postman export keeps folder auth and omits secrets by default', () {
      final plan = parsePostmanCollection(postman);
      final out = exportPostmanCollection(plan.collections.single);
      final text = jsonEncode(out);
      expect(out['auth'], isNotNull);
      expect(text, isNot(contains('col-tok')));
      final folder = (out['item'] as List).first as Map<String, dynamic>;
      expect(folder['auth'], isNotNull);
      expect((folder['variable'] as List).single['key'], 'fv');
      final withSecrets = jsonEncode(
        exportPostmanCollection(plan.collections.single, includeSecrets: true),
      );
      expect(withSecrets, contains('col-tok'));
    });

    test(
      'PostBox format round trip keeps settings and drops scripts on import',
      () {
        final col = ImportedCollection(
          name: 'C',
          settings: NodeSettings(
            auth: const AuthConfig(
              type: AuthType.bearer,
              token: 'secret-token',
            ),
            headers: const <KeyValue>[KeyValue(key: 'X-A', value: '1')],
            preScript: 'log("collection script");',
          ),
          nodes: <ImportedNode>[
            ImportedNode.folder(
              'F',
              <ImportedNode>[
                ImportedNode.request(
                  RequestModel(
                    id: 'r1',
                    url: 'https://x.test',
                    preScript: 'log("request script");',
                    postScript: 'test("t", true);',
                    variables: const <KeyValue>[
                      KeyValue(key: 'rv', value: '1'),
                    ],
                  ),
                ),
              ],
              settings: NodeSettings(
                variables: <Variable>[_v('fv', 'folder-secret', secret: true)],
                postScript: 'log("folder script");',
              ),
            ),
          ],
        );
        final json = jsonEncode(
          exportPostBox(collections: <ImportedCollection>[col]),
        );
        expect(json, isNot(contains('secret-token')));
        expect(json, isNot(contains('folder-secret')));

        final plan = parsePostBox(json);
        expect(plan.hasErrors, isFalse);
        final back = plan.collections.single;
        expect(back.settings.auth.type, AuthType.bearer);
        expect(back.settings.headers.single.key, 'X-A');
        expect(back.settings.preScript, ''); // never imported
        final folder = back.nodes.single;
        expect(folder.settings.postScript, '');
        expect(folder.settings.variables.single.key, 'fv');
        final req = folder.children.single.request!;
        expect(req.preScript, '');
        expect(req.postScript, '');
        expect(req.variables.single.key, 'rv');
        expect(plan.notes.any((n) => n.message.contains('script')), isTrue);
      },
    );

    test('folder variable ids are fresh on import', () {
      final col = ImportedCollection(
        name: 'C',
        nodes: <ImportedNode>[
          ImportedNode.folder(
            'F',
            const <ImportedNode>[],
            settings: NodeSettings(variables: <Variable>[_v('a', '1')]),
          ),
        ],
      );
      final json = jsonEncode(
        exportPostBox(collections: <ImportedCollection>[col]),
      );
      final a = parsePostBox(
        json,
      ).collections.single.nodes.single.settings.variables.single.id;
      final b = parsePostBox(
        json,
      ).collections.single.nodes.single.settings.variables.single.id;
      expect(a, isNot(b));
      expect(a, isNot('id-a'));
    });

    test('cURL export of a binary body uses --data-binary with the file', () {
      final out = exportCurl(
        RequestModel(
          id: 'r',
          method: 'POST',
          url: 'https://x.test/up',
          bodyType: BodyType.binary,
          body: '/tmp/my file.bin',
        ),
      );
      expect(out, contains('--data-binary'));
      expect(out, contains('@/tmp/my file.bin'));
      expect(out, contains('application/octet-stream'));
    });

    test('Postman export of a binary body uses mode file', () {
      final col = ImportedCollection(
        name: 'B',
        nodes: <ImportedNode>[
          ImportedNode.request(
            RequestModel(
              id: 'r',
              method: 'POST',
              url: 'https://x.test',
              bodyType: BodyType.binary,
              body: '/tmp/a.bin',
            ),
          ),
        ],
      );
      final item =
          (exportPostmanCollection(col)['item'] as List).single
              as Map<String, dynamic>;
      expect(item['request']['body']['mode'], 'file');
    });
  });
}
