import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/app/services.dart';
import 'package:postbox/features/collections/application/collections_cubit.dart';
import 'package:postbox/features/environments/application/environments_cubit.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/history/application/history_cubit.dart';
import 'package:postbox/features/http/domain/http_engine.dart';
import 'package:postbox/features/requests/domain/request_models.dart';
import 'package:postbox/features/runner/application/runner_cubit.dart';
import 'package:postbox/features/settings/application/settings_cubit.dart';
import 'package:postbox/features/testing/domain/assertions.dart';
import 'package:postbox/features/workspace/application/workspace_cubit.dart';

/// Integration tests: real cubits, in-memory SQLite and a local HTTP server.
void main() {
  late HttpServer server;
  late AppServices services;
  late SettingsCubit settings;
  late EnvironmentsCubit envs;
  late CollectionsCubit cols;
  late HistoryCubit history;
  late WorkspaceCubit ws;
  late String base;
  final seenAuth = <String?>[];

  setUp(() async {
    seenAuth.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      try {
      seenAuth.add(req.headers.value('authorization'));
      req.response.headers.contentType = ContentType.json;
      final path = req.uri.path;
      if (path == '/login') {
        req.response.write(jsonEncode(<String, String>{'token': 'T1'}));
      } else if (path == '/me/T1') {
        req.response.write(jsonEncode(<String, String>{'user': 'ok'}));
      } else if (path == '/slow') {
        await Future<void>.delayed(const Duration(seconds: 2));
      } else if (path.startsWith('/me/')) {
        req.response.statusCode = 404;
      } else {
        req.response.write('{"token":"abc"}');
      }
      await req.response.close();
      } on Object {
        // The client may have disconnected (cancelled requests); ignore.
      }
    });
    services = AppServices.inMemory();
    settings = SettingsCubit(services.settingsRepository);
    envs = EnvironmentsCubit(services.environments, services.vault);
    cols = CollectionsCubit(services.collections, services.vault);
    history = HistoryCubit(services.history);
    ws = WorkspaceCubit(
      collections: cols,
      environments: envs,
      settings: settings,
      history: history,
      executor: services.executor,
      log: services.log,
    );
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

  test('send: result, assertions, chaining into globals, history', () async {
    ws.newTab(
      model: RequestModel(
        id: 'r1',
        url: '$base/anything?x=1',
        assertions: <Assertion>[
          Assertion(id: 'a', kind: AssertionKind.statusEquals, expected: '200'),
          Assertion(id: 'b', kind: AssertionKind.jsonPathEquals, target: r'$.token', expected: 'abc'),
        ],
        extractions: <Extraction>[
          Extraction(id: 'e', variable: 'tok', source: ExtractionSource.jsonPath, expression: r'$.token'),
        ],
      ),
    );
    await ws.send('r1');
    final tab = ws.state.tab('r1')!;
    expect(tab.phase, SendPhase.idle);
    expect(tab.outcome!.result!.statusCode, 200);
    expect(tab.outcome!.assertionsPassed, isTrue);
    // No active environment, so extracted values go to globals.
    expect(envs.state.globals.single.key, 'tok');
    expect(envs.state.globals.single.value, 'abc');
    expect(history.state.entries.single.status, 200);
    // Default privacy: query values masked, request body not stored.
    expect(history.state.entries.single.url, '$base/anything?x=••••');
    expect(history.state.entries.single.requestJson, isNull);
  });

  test('extraction goes into the active environment when there is one', () async {
    final env = await envs.create('Dev');
    await envs.setActive(env.id);
    ws.newTab(
      model: RequestModel(
        id: 'r1',
        url: '$base/login',
        extractions: <Extraction>[
          Extraction(id: 'e', variable: 'tok', source: ExtractionSource.jsonPath, expression: r'$.token'),
        ],
      ),
    );
    await ws.send('r1');
    expect(envs.state.active!.variables.single.value, 'T1');
    expect(envs.state.globals, isEmpty);
  });

  test('variables from environment are used when sending', () async {
    final env = await envs.create('Dev');
    await envs.setActive(env.id);
    await envs.setExtracted(<String, String>{'path': 'me/T1'});
    ws.newTab(model: RequestModel(id: 'r1', url: '$base/{{path}}'));
    await ws.send('r1');
    expect(ws.state.tab('r1')!.outcome!.result!.statusCode, 200);
  });

  test('build errors are reported without sending', () async {
    ws.newTab(model: RequestModel(id: 'r1', url: '{{missing}}/x'));
    await ws.send('r1');
    final o = ws.state.tab('r1')!.outcome!;
    expect(o.buildError!.code, 'unresolved_url');
    expect(o.result, isNull);
    expect(history.state.entries, isEmpty);
  });

  test('cancel produces a cancelled failure and no history entry', () async {
    ws.newTab(model: RequestModel(id: 'r1', url: '$base/slow'));
    final f = ws.send('r1');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ws.state.tab('r1')!.phase, SendPhase.sending);
    ws.cancel('r1');
    await f;
    final o = ws.state.tab('r1')!.outcome!;
    expect(o.failure!.kind, HttpFailureKind.cancelled);
    expect(history.state.entries, isEmpty);
  });

  test('history with privacy off keeps a replayable request without secrets', () async {
    await settings.update((s) => s.copyWith(omitSensitiveInHistory: false));
    ws.newTab(
      model: RequestModel(
        id: 'r1',
        url: '$base/x',
        auth: const AuthConfig(type: AuthType.bearer, token: 'TOPSECRET'),
      ),
    );
    await ws.send('r1');
    final e = history.state.entries.single;
    expect(e.requestJson, isNotNull);
    expect(e.requestJson!.contains('TOPSECRET'), isFalse);
    expect(e.url.contains('TOPSECRET'), isFalse);
    expect(seenAuth.single, 'Bearer TOPSECRET');
  });

  test('history can be switched off', () async {
    await settings.update((s) => s.copyWith(persistHistory: false));
    ws.newTab(model: RequestModel(id: 'r1', url: '$base/x'));
    await ws.send('r1');
    expect(history.state.entries, isEmpty);
  });

  test('save keeps secrets out of the database and restores them', () async {
    final col = await cols.createCollection('C');
    ws.newTab(
      model: RequestModel(
        id: 'r1',
        name: 'Secret req',
        url: '$base/x',
        auth: const AuthConfig(type: AuthType.bearer, token: 'TOPSECRET'),
      ),
    );
    expect(ws.state.tab('r1')!.dirty, isTrue);
    await ws.save('r1', collectionId: col.id);
    expect(ws.state.tab('r1')!.dirty, isFalse);
    final raw = services.database.db
        .select('SELECT data_json FROM nodes WHERE id = ?', <Object?>['r1'])
        .first['data_json'] as String;
    expect(raw.contains('TOPSECRET'), isFalse);

    final node = cols.state.node('r1')!;
    final full = await cols.loadFullRequest(node);
    expect(full.auth.token, 'TOPSECRET');

    // Editing makes the tab dirty again; closing the last tab leaves a blank one.
    ws.update('r1', ws.state.tab('r1')!.draft.copyWith(url: '$base/y'));
    expect(ws.state.tab('r1')!.dirty, isTrue);
    await ws.closeTab('r1');
    expect(ws.state.tabs.length, 1);
    expect(ws.state.tabs.single.id, isNot('r1'));
  });

  test('opening a saved node twice focuses the same tab', () async {
    final col = await cols.createCollection('C');
    final node = await cols.saveRequest(
      request: RequestModel(id: 'r9', name: 'N', url: '$base/x'),
      collectionId: col.id,
    );
    await ws.openNode(node);
    await ws.openNode(node);
    expect(ws.state.tabs.where((t) => t.id == 'r9').length, 1);
    expect(ws.state.activeId, 'r9');
  });

  test('deleting a collection removes request secrets', () async {
    final col = await cols.createCollection('C');
    await cols.saveRequest(
      request: RequestModel(
        id: 'r1',
        url: '$base/x',
        auth: const AuthConfig(type: AuthType.bearer, token: 'TOPSECRET'),
      ),
      collectionId: col.id,
    );
    expect(await services.secrets.read('req.r1.token'), 'TOPSECRET');
    await cols.deleteCollection(col.id);
    expect(await services.secrets.read('req.r1.token'), isNull);
  });

  test('duplicate copies secrets to the new request', () async {
    final col = await cols.createCollection('C');
    await cols.saveRequest(
      request: RequestModel(
        id: 'r1',
        name: 'A',
        url: '$base/x',
        auth: const AuthConfig(type: AuthType.bearer, token: 'TOPSECRET'),
      ),
      collectionId: col.id,
    );
    await cols.duplicate('r1');
    final copy = cols.state.nodes.firstWhere((n) => n.id != 'r1');
    final full = await cols.loadFullRequest(copy);
    expect(full.auth.token, 'TOPSECRET');
    expect(copy.name, 'A copy');
  });

  test('secret environment variables are stored outside the database', () async {
    final env = await envs.create('Prod');
    await envs.save(env.copyWith(variables: const <Variable>[
      Variable(id: 'v1', key: 'api', value: 'S3CRETVALUE', secret: true),
      Variable(id: 'v2', key: 'host', value: 'h'),
    ]));
    final raw = services.database.db.select('SELECT vars_json FROM environments').first['vars_json'] as String;
    expect(raw.contains('S3CRETVALUE'), isFalse);
    expect(await services.secrets.read('var.v1'), 'S3CRETVALUE');
    // Reload (as after an app restart) restores the secret value.
    final again = EnvironmentsCubit(services.environments, services.vault);
    await again.load();
    expect(again.state.environments.single.variables.firstWhere((v) => v.key == 'api').value, 'S3CRETVALUE');
    await again.close();
  });

  test('runner chains values between requests and does not persist them', () async {
    final col = await cols.createCollection('Flow');
    await cols.saveRequest(
      request: RequestModel(
        id: 'a',
        name: 'login',
        url: '$base/login',
        extractions: <Extraction>[
          Extraction(id: 'e', variable: 'tok', source: ExtractionSource.jsonPath, expression: r'$.token'),
        ],
      ),
      collectionId: col.id,
    );
    await cols.saveRequest(
      request: RequestModel(
        id: 'b',
        name: 'me',
        url: '$base/me/{{tok}}',
        assertions: <Assertion>[Assertion(id: 'x', kind: AssertionKind.statusEquals, expected: '200')],
      ),
      collectionId: col.id,
    );
    await cols.saveRequest(
      request: RequestModel(id: 'c', name: 'wrong', url: '$base/me/other'),
      collectionId: col.id,
    );
    final runner = RunnerCubit(
      collections: cols,
      environments: envs,
      settings: settings,
      executor: services.executor,
    );
    addTearDown(runner.close);
    await runner.run(col.id);
    final s = runner.state;
    expect(s.running, isFalse);
    expect(s.results.map((r) => r.name), <String>['login', 'me', 'wrong']);
    expect(s.results.map((r) => r.passed), <bool>[true, true, false]);
    expect(envs.state.globals, isEmpty);
    expect(s.toMarkdown(), contains('FAIL'));
    expect(jsonDecode(s.toJsonString())['failed'], 1);

    await runner.run(col.id, stopOnFailure: true);
    expect(runner.state.results.length, 3);
  });
}
