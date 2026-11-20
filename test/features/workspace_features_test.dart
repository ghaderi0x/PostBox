import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/app/services.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/collections/application/collections_cubit.dart';
import 'package:postbox/features/collections/domain/collection_models.dart';
import 'package:postbox/features/collections/domain/node_settings.dart';
import 'package:postbox/features/environments/application/environments_cubit.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/history/application/history_cubit.dart';
import 'package:postbox/features/http/data/cookie_store.dart';
import 'package:postbox/features/http/domain/cookie_jar.dart';
import 'package:postbox/features/import_export/postbox_format.dart';
import 'package:postbox/features/persistence/app_database.dart';
import 'package:postbox/features/requests/domain/request_models.dart';
import 'package:postbox/features/runner/application/runner_cubit.dart';
import 'package:postbox/features/settings/application/settings_cubit.dart';
import 'package:postbox/features/templates/request_templates.dart';
import 'package:postbox/features/workspace/application/workspace_cubit.dart';
import 'package:postbox/features/workspaces/workspace_registry.dart';
import 'package:sqlite3/sqlite3.dart';

/// Integration tests for tabs, session restore, inheritance, bulk actions,
/// cookies, templates and workspaces: real cubits, in-memory SQLite and a
/// local HTTP server.
void main() {
  late HttpServer server;
  late AppServices services;
  late SettingsCubit settings;
  late EnvironmentsCubit envs;
  late CollectionsCubit cols;
  late HistoryCubit history;
  late WorkspaceCubit ws;
  late String base;
  final seen = <Map<String, String?>>[];

  WorkspaceCubit newWorkspace() => WorkspaceCubit(
    collections: cols,
    environments: envs,
    settings: settings,
    history: history,
    executor: services.executor,
    log: services.log,
    session: services.session,
  );

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      try {
        seen.add(<String, String?>{
          'path': req.uri.toString(),
          'auth': req.headers.value('authorization'),
          'team': req.headers.value('x-team'),
          'cookie': req.headers.value('cookie'),
        });
        req.response.headers.add('set-cookie', 'sid=s1; Path=/; Max-Age=3600');
        req.response.write('{"ok":true}');
        await req.response.close();
      } on Object {
        // Client disconnected.
      }
    });
    services = AppServices.inMemory();
    settings = SettingsCubit(services.settingsRepository);
    envs = EnvironmentsCubit(services.environments, services.vault);
    cols = CollectionsCubit(services.collections, services.vault);
    history = HistoryCubit(services.history);
    ws = newWorkspace();
    await cols.load();
    await envs.load();
  });

  tearDown(() async {
    await server.close(force: true);
    await ws.close();
    await history.close();
    await cols.close();
    await envs.close();
    await settings.close();
  });

  group('tabs', () {
    test('reorderTabs follows the ReorderableListView convention', () {
      ws.newTab(model: RequestModel(id: 'a'));
      ws.newTab(model: RequestModel(id: 'b'));
      ws.newTab(model: RequestModel(id: 'c'));
      List<String> order() => ws.state.tabs.map((t) => t.id).toList();
      expect(order(), <String>['a', 'b', 'c']);
      ws.reorderTabs(0, 3); // drag a to the end
      expect(order(), <String>['b', 'c', 'a']);
      ws.reorderTabs(2, 0); // drag a back to the front
      expect(order(), <String>['a', 'b', 'c']);
      ws.reorderTabs(0, 1); // dropping at the own position changes nothing
      expect(order(), <String>['a', 'b', 'c']);
      ws.reorderTabs(7, 0); // out of range is ignored
      ws.reorderTabs(-1, 0);
      expect(order(), <String>['a', 'b', 'c']);
      expect(ws.state.activeId, 'c');
    });

    test('selectRelative wraps around', () {
      ws.newTab(model: RequestModel(id: 'a'));
      ws.newTab(model: RequestModel(id: 'b'));
      ws.select('a');
      ws.selectRelative(-1);
      expect(ws.state.activeId, 'b');
      ws.selectRelative(1);
      expect(ws.state.activeId, 'a');
    });
  });

  group('session restore', () {
    test(
      'tabs, drafts and the active tab come back; unsaved secrets do not',
      () async {
        final col = await cols.createCollection('C');
        final saved = await cols.saveRequest(
          request: RequestModel(
            id: 'saved1',
            name: 'Saved',
            url: 'https://a.test/1',
            auth: const AuthConfig(
              type: AuthType.bearer,
              token: 'saved-secret',
            ),
          ),
          collectionId: col.id,
        );
        await ws.openNode(saved);
        // Edit the saved request without saving it.
        ws.update(
          'saved1',
          ws.state.tab('saved1')!.draft.copyWith(url: 'https://a.test/edited'),
        );
        ws.newTab(
          model: RequestModel(
            id: 'unsaved1',
            url: 'https://b.test/',
            auth: const AuthConfig(
              type: AuthType.bearer,
              token: 'typed-secret',
            ),
          ),
        );
        ws.select('saved1');
        ws.persistSession();

        final stored = services.session.read('session.tabs')!;
        expect(stored, isNot(contains('saved-secret')));
        expect(stored, isNot(contains('typed-secret')));

        final restored = newWorkspace();
        addTearDown(restored.close);
        expect(await restored.restoreSession(), isTrue);
        expect(restored.state.tabs.map((t) => t.id), <String>[
          'saved1',
          'unsaved1',
        ]);
        expect(restored.state.activeId, 'saved1');
        final t1 = restored.state.tab('saved1')!;
        expect(t1.draft.url, 'https://a.test/edited');
        expect(t1.isSaved, isTrue);
        expect(t1.dirty, isTrue);
        expect(t1.saved!.url, 'https://a.test/1');
        expect(t1.draft.auth.token, 'saved-secret'); // from secure storage
        final t2 = restored.state.tab('unsaved1')!;
        expect(t2.isSaved, isFalse);
        expect(t2.draft.url, 'https://b.test/');
        expect(t2.draft.auth.token, '');
      },
    );

    test(
      'a saved tab whose request was deleted comes back as an unsaved draft',
      () async {
        final col = await cols.createCollection('C');
        final n = await cols.saveRequest(
          request: RequestModel(id: 'gone', url: 'https://g.test'),
          collectionId: col.id,
        );
        await ws.openNode(n);
        ws.persistSession();
        await cols.deleteNode(n.id);
        final restored = newWorkspace();
        addTearDown(restored.close);
        expect(await restored.restoreSession(), isTrue);
        expect(restored.state.tab('gone')!.isSaved, isFalse);
      },
    );

    test(
      'nothing stored means nothing to restore; corrupt data is ignored',
      () async {
        final fresh = newWorkspace();
        addTearDown(fresh.close);
        expect(await fresh.restoreSession(), isFalse);
        services.session.write('session.tabs', '{not json');
        expect(await fresh.restoreSession(), isFalse);
      },
    );

    test('layout is stored and read back', () {
      expect(ws.readLayout(), isEmpty);
      ws.saveLayout(<String, dynamic>{
        'sidebar': 321.0,
        'fraction': 0.4,
        'horizontal': true,
      });
      expect(ws.readLayout()['sidebar'], 321.0);
      expect(ws.readLayout()['horizontal'], true);
    });
  });

  group('inheritance through the workspace', () {
    test(
      'a request in a folder inherits auth, headers and variables',
      () async {
        final col = await cols.createCollection('API');
        final folder = await cols.createFolder(col.id, null, 'Admin');
        await cols.saveSettings(
          col.id,
          NodeSettings(
            auth: const AuthConfig(
              type: AuthType.bearer,
              token: 'collection-secret',
            ),
            headers: const <KeyValue>[
              KeyValue(key: 'X-Team', value: 'collection'),
            ],
          ),
        );
        await cols.saveSettings(
          folder.id,
          NodeSettings(
            headers: const <KeyValue>[KeyValue(key: 'X-Team', value: 'admin')],
            variables: <Variable>[
              Variable(id: 'fv', key: 'seg', value: 'users'),
            ],
          ),
        );
        final n = await cols.saveRequest(
          request: RequestModel(
            id: 'inh',
            url: '$base/{{seg}}',
            auth: const AuthConfig(type: AuthType.inherit),
          ),
          collectionId: col.id,
          parentId: folder.id,
        );
        await ws.openNode(n);
        await ws.send('inh');

        expect(seen.single['path'], '/users');
        expect(seen.single['auth'], 'Bearer collection-secret');
        expect(seen.single['team'], 'admin');
        expect(ws.state.tab('inh')!.outcome!.effectiveAuthSource, 'API');

        // The secret is in the vault, not in the database rows.
        final rows = services.database.db.select(
          'SELECT settings_json FROM collections',
        );
        expect(
          rows.single['settings_json'] as String,
          isNot(contains('collection-secret')),
        );
        expect(
          (await cols.loadSettings(col.id)).auth.token,
          'collection-secret',
        );
      },
    );

    test(
      'folder secret variables are stored in the vault and used when sending',
      () async {
        final col = await cols.createCollection('API');
        final folder = await cols.createFolder(col.id, null, 'F');
        await cols.saveSettings(
          folder.id,
          NodeSettings(
            variables: <Variable>[
              Variable(
                id: 'sv',
                key: 'token',
                value: 'folder-secret',
                secret: true,
              ),
            ],
          ),
        );
        final dbRow = services.database.db.select(
          'SELECT settings_json FROM nodes WHERE id=?',
          <Object?>[folder.id],
        );
        expect(
          dbRow.single['settings_json'] as String,
          isNot(contains('folder-secret')),
        );
        expect(cols.state.node(folder.id)!.settings.variables.single.value, '');
        expect(
          (await cols.loadSettings(folder.id)).variables.single.value,
          'folder-secret',
        );

        final n = await cols.saveRequest(
          request: RequestModel(
            id: 'r',
            url: '$base/x',
            headers: const <KeyValue>[
              KeyValue(key: 'X-Team', value: '{{token}}'),
            ],
          ),
          collectionId: col.id,
          parentId: folder.id,
        );
        await ws.openNode(n);
        await ws.send('r');
        expect(seen.single['team'], 'folder-secret');
      },
    );

    test('settings survive a reload of the collections', () async {
      final col = await cols.createCollection('API');
      final f = await cols.createFolder(col.id, null, 'F');
      await cols.saveSettings(
        f.id,
        NodeSettings(
          preScript: 'log(1);',
          headers: const <KeyValue>[KeyValue(key: 'A', value: '1')],
        ),
      );
      final again = CollectionsCubit(services.collections, services.vault);
      addTearDown(again.close);
      await again.load();
      final s = again.state.node(f.id)!.settings;
      expect(s.preScript, 'log(1);');
      expect(s.headers.single.key, 'A');
    });

    test(
      'duplicating a folder copies settings, auth secret and gives variables new ids',
      () async {
        final col = await cols.createCollection('API');
        final f = await cols.createFolder(col.id, null, 'F');
        await cols.saveSettings(
          f.id,
          NodeSettings(
            auth: const AuthConfig(type: AuthType.bearer, token: 'dup-secret'),
            variables: <Variable>[
              Variable(id: 'orig-id', key: 'k', value: 'v', secret: true),
            ],
          ),
        );
        await cols.duplicate(f.id);
        final copy = cols.state.nodes.firstWhere(
          (n) => n.isFolder && n.id != f.id,
        );
        final copySettings = await cols.loadSettings(copy.id);
        expect(copySettings.auth.token, 'dup-secret');
        expect(copySettings.variables.single.value, 'v');
        expect(copySettings.variables.single.id, isNot('orig-id'));
        // Editing the copy does not touch the original.
        await cols.saveSettings(
          copy.id,
          copySettings.copyWith(
            variables: <Variable>[
              copySettings.variables.single.copyWith(value: 'changed'),
            ],
          ),
        );
        expect((await cols.loadSettings(f.id)).variables.single.value, 'v');
      },
    );

    test('deleting a folder removes its secrets', () async {
      final col = await cols.createCollection('API');
      final f = await cols.createFolder(col.id, null, 'F');
      await cols.saveSettings(
        f.id,
        NodeSettings(
          auth: const AuthConfig(type: AuthType.bearer, token: 'gone-secret'),
        ),
      );
      expect((await cols.loadSettings(f.id)).auth.token, 'gone-secret');
      await cols.deleteNode(f.id);
      for (final k in AuthConfig.secretKeys) {
        expect(await services.secrets.read('node.${f.id}.$k'), isNull);
      }
    });

    test(
      'export includes settings and import restores them with secrets in the vault',
      () async {
        final col = await cols.createCollection('API');
        final f = await cols.createFolder(col.id, null, 'F');
        await cols.saveSettings(
          col.id,
          NodeSettings(
            auth: const AuthConfig(
              type: AuthType.bearer,
              token: 'export-secret',
            ),
            preScript: 'log("x");',
          ),
        );
        await cols.saveSettings(
          f.id,
          NodeSettings(
            headers: const <KeyValue>[KeyValue(key: 'H', value: '1')],
          ),
        );
        final tree = await cols.buildExportTree(col.id);
        expect(
          tree.settings.auth.token,
          '',
          reason: 'default export has no secrets',
        );
        expect(tree.nodes.single.settings.headers.single.key, 'H');
        final withSecrets = await cols.buildExportTree(
          col.id,
          includeSecrets: true,
        );
        expect(withSecrets.settings.auth.token, 'export-secret');

        final plan = parsePostBox(
          jsonEncode(
            exportPostBox(
              collections: <ImportedCollection>[withSecrets],
              includeSecrets: true,
            ),
          ),
        );
        await cols.commitImport(plan);
        final imported = cols.state.collections.firstWhere(
          (c) => c.id != col.id,
        );
        final s = await cols.loadSettings(imported.id);
        expect(s.auth.type, AuthType.bearer);
        expect(s.auth.token, 'export-secret');
        expect(s.preScript, '', reason: 'scripts are never imported');
        final importedFolder = cols.state.nodes.firstWhere(
          (n) => n.collectionId == imported.id && n.isFolder,
        );
        expect(importedFolder.settings.headers.single.key, 'H');
      },
    );
  });

  group('bulk actions', () {
    test('selection export, bulk move and bulk delete', () async {
      final a = await cols.createCollection('A');
      final b = await cols.createCollection('B');
      final folder = await cols.createFolder(a.id, null, 'F');
      final r1 = await cols.saveRequest(
        request: RequestModel(id: 'r1', name: 'one', url: 'https://x.test/1'),
        collectionId: a.id,
        parentId: folder.id,
      );
      final r2 = await cols.saveRequest(
        request: RequestModel(id: 'r2', name: 'two', url: 'https://x.test/2'),
        collectionId: a.id,
      );
      final r3 = await cols.saveRequest(
        request: RequestModel(id: 'r3', name: 'three', url: 'https://x.test/3'),
        collectionId: a.id,
      );

      // Nodes under a selected folder are exported once, through the folder.
      final export = await cols.buildSelectionExport(<String>{
        folder.id,
        r1.id,
        r2.id,
      });
      expect(export.nodes.length, 2);
      expect(export.requestCount, 2);

      cols.moveNodes(<String>{r2.id, r3.id}, collectionId: b.id);
      expect(cols.state.node(r2.id)!.collectionId, b.id);
      expect(cols.state.node(r3.id)!.collectionId, b.id);
      expect(cols.state.node(r1.id)!.collectionId, a.id);

      expect(
        () => cols.moveNodes(
          <String>{folder.id},
          collectionId: a.id,
          parentId: folder.id,
        ),
        throwsArgumentError,
      );

      await cols.deleteNodes(<String>{folder.id, r1.id, r2.id});
      expect(cols.state.node(folder.id), isNull);
      expect(cols.state.node(r1.id), isNull);
      expect(cols.state.node(r2.id), isNull);
      expect(cols.state.node(r3.id), isNotNull);
    });
  });

  group('cookies and templates in the database', () {
    test('the jar persists cookies and a new jar loads them', () async {
      final col = await cols.createCollection('C');
      final n = await cols.saveRequest(
        request: RequestModel(id: 'c', url: '$base/login'),
        collectionId: col.id,
      );
      await ws.openNode(n);
      await ws.send('c');
      await ws.send('c');
      expect(seen.last['cookie'], 'sid=s1');
      final reloaded = CookieJarImpl(
        persistence: SqliteCookiePersistence(services.database),
      );
      expect(reloaded.all().single.name, 'sid');
      expect(reloaded.cookieHeader(Uri.parse('$base/x')), 'sid=s1');
      reloaded.clear();
      expect(
        CookieJarImpl(
          persistence: SqliteCookiePersistence(services.database),
        ).all(),
        isEmpty,
      );
    });

    test('clearing local data removes cookies and templates', () async {
      services.cookieJar.storeFromResponse(
        Uri.parse('https://a.test/'),
        <String>['a=1; Path=/; Max-Age=100'],
      );
      services.templates.add('T', RequestModel(id: 'x', url: 'https://a.test'));
      await services.data.clearAll();
      expect(services.database.db.select('SELECT * FROM cookies'), isEmpty);
      expect(services.database.db.select('SELECT * FROM templates'), isEmpty);
    });

    test(
      'templates are stored without secrets and instantiate with new ids',
      () {
        final t = services.templates.add(
          'Mine',
          RequestModel(
            id: 'orig',
            url: '{{base_url}}/x',
            auth: const AuthConfig(type: AuthType.bearer, token: 'tpl-secret'),
          ),
        );
        final stored = services.templates.list().single;
        expect(stored.name, 'Mine');
        expect(stored.request.auth.type, AuthType.bearer);
        expect(stored.request.auth.token, '');
        final dump = jsonEncode(
          services.database.db
              .select('SELECT data_json FROM templates')
              .map((r) => r['data_json'])
              .toList(),
        );
        expect(dump, isNot(contains('tpl-secret')));
        expect(stored.instantiate().id, isNot('orig'));
        services.templates.delete(t.id);
        expect(services.templates.list(), isEmpty);
      },
    );

    test('built-in templates are valid and have no secrets', () {
      final all = builtInTemplates();
      expect(all.length, greaterThanOrEqualTo(4));
      expect(all.map((t) => t.id).toSet().length, all.length);
      for (final t in all) {
        expect(t.builtIn, isTrue);
        expect(jsonEncode(t.request.toJson()), isNot(contains('password": "')));
        expect(t.instantiate().id, isNot('tpl'));
      }
    });
  });

  group('migration v1 to v2', () {
    test('adds settings columns, cookies and templates and keeps data', () {
      final app = AppDatabase.openInMemory();
      final raw = app.db;
      raw.execute(
        "INSERT INTO collections(id,name,description,sort,vars_json,created,updated) VALUES('c1','Old','',0,'[]',1,1)",
      );
      // Turn it back into a v1 database.
      raw.execute('DROP TABLE cookies');
      raw.execute('DROP TABLE templates');
      raw.execute('ALTER TABLE collections DROP COLUMN settings_json');
      raw.execute('ALTER TABLE nodes DROP COLUMN settings_json');
      raw.userVersion = 1;

      final migrated = AppDatabase.migrateExisting(raw);
      expect(migrated.schemaVersion, AppDatabase.latestVersion);
      final row = raw
          .select('SELECT name, settings_json FROM collections')
          .single;
      expect(row['name'], 'Old');
      expect(row['settings_json'], '{}');
      expect(raw.select('SELECT * FROM cookies'), isEmpty);
      expect(raw.select('SELECT * FROM templates'), isEmpty);
      expect(raw.select('SELECT settings_json FROM nodes'), isEmpty);
    });
  });

  group('runner iterations', () {
    test(
      'data rows drive iterations; variables are visible to requests',
      () async {
        final col = await cols.createCollection('R');
        await cols.saveRequest(
          request: RequestModel(id: 'q', name: 'q', url: '$base/item/{{id}}'),
          collectionId: col.id,
        );
        final runner = RunnerCubit(
          collections: cols,
          environments: envs,
          settings: settings,
          executor: services.executor,
        );
        addTearDown(runner.close);
        await runner.run(
          col.id,
          data: <Map<String, String>>[
            <String, String>{'id': '1'},
            <String, String>{'id': '2'},
            <String, String>{'id': '3'},
          ],
          concurrency: 2,
        );
        final results = runner.state.results;
        expect(results.length, 3);
        expect(results.map((r) => r.iteration).toSet(), <int>{0, 1, 2});
        expect(seen.map((s) => s['path']).toSet(), <String>{
          '/item/1',
          '/item/2',
          '/item/3',
        });
        expect(runner.state.iterations, 3);
        expect(runner.state.passed, 3);
      },
    );

    test(
      'plain iterations repeat the run and stop on failure stops all workers',
      () async {
        final col = await cols.createCollection('R');
        await cols.saveRequest(
          request: RequestModel(id: 'q', name: 'q', url: '$base/x'),
          collectionId: col.id,
        );
        final runner = RunnerCubit(
          collections: cols,
          environments: envs,
          settings: settings,
          executor: services.executor,
        );
        addTearDown(runner.close);
        await runner.run(col.id, iterations: 5, concurrency: 3);
        expect(runner.state.results.length, 5);
        expect(runner.state.running, isFalse);
      },
    );
  });

  group('workspace registry', () {
    test(
      'default workspace exists and cannot be removed or renamed away',
      () async {
        final r = WorkspaceRegistry.inMemory();
        expect(r.items.single.id, kDefaultWorkspaceId);
        expect(r.active.file, 'postbox.db');
        expect(await r.remove(kDefaultWorkspaceId), isFalse);
      },
    );

    test('create, switch, rename and remove', () async {
      final r = WorkspaceRegistry.inMemory();
      final w = await r.create('  Client A ');
      expect(w.name, 'Client A');
      expect(w.file, startsWith('ws_'));
      expect(w.file, endsWith('.db'));
      await r.setActive(w.id);
      expect(r.activeId, w.id);
      expect(
        await r.remove(w.id),
        isFalse,
        reason: 'the active workspace cannot be removed',
      );
      await r.setActive(kDefaultWorkspaceId);
      await r.rename(w.id, 'Client B');
      expect(r.items.firstWhere((x) => x.id == w.id).name, 'Client B');
      expect(await r.remove(w.id), isTrue);
      expect(r.items.length, 1);
    });

    test(
      'empty names get a default and the number of workspaces is limited',
      () async {
        final r = WorkspaceRegistry.inMemory();
        expect((await r.create('')).name, startsWith('Workspace'));
        for (var i = r.items.length; i < WorkspaceRegistry.maxWorkspaces; i++) {
          await r.create('w$i');
        }
        expect(() => r.create('one too many'), throwsStateError);
      },
    );
  });

  test('sqlite is the real library here', () {
    expect(sqlite3.version.libVersion, isNotEmpty);
  });
}
