import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/collections/data/collection_repository.dart';
import 'package:postbox/features/collections/domain/collection_models.dart';
import 'package:postbox/features/environments/data/environment_repository.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/history/data/history_repository.dart';
import 'package:postbox/features/history/domain/history_models.dart';
import 'package:postbox/features/persistence/app_database.dart';
import 'package:postbox/features/requests/domain/request_models.dart';
import 'package:sqlite3/sqlite3.dart';

// These tests use the real SQLite library through package:sqlite3 (in-memory).

void main() {
  late AppDatabase db;
  late SqliteCollectionRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    repo = SqliteCollectionRepository(db);
  });

  RequestModel req(String id, String name) =>
      RequestModel(id: id, name: name, url: 'https://a.test/$name');

  group('migrations', () {
    test('fresh database is at the latest version', () {
      expect(db.schemaVersion, AppDatabase.latestVersion);
    });

    test('an empty v0 database is migrated, and migrating again is a no-op', () {
      final raw = sqlite3.openInMemory();
      expect(raw.userVersion, 0);
      final migrated = AppDatabase.migrateExisting(raw);
      expect(migrated.schemaVersion, AppDatabase.latestVersion);
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, containsAll(<String>['collections', 'nodes', 'environments', 'history', 'kv']));
      AppDatabase.migrateExisting(raw);
      expect(raw.userVersion, AppDatabase.latestVersion);
    });

    test('a database from a newer app version is refused', () {
      final raw = sqlite3.openInMemory()..userVersion = 999;
      expect(() => AppDatabase.migrateExisting(raw), throwsStateError);
    });

    test('a failing migration step rolls back', () {
      final raw = sqlite3.openInMemory();
      raw.execute('BEGIN');
      raw.execute('CREATE TABLE t(a)');
      raw.execute('ROLLBACK');
      final app = AppDatabase.migrateExisting(raw);
      expect(() => app.transaction<void>(() {
            app.db.execute("INSERT INTO kv(key,value) VALUES('a','1')");
            throw StateError('boom');
          }), throwsStateError);
      expect(app.db.select('SELECT * FROM kv'), isEmpty);
    });
  });

  group('collections', () {
    test('create, update with variables, list, delete', () {
      final c = repo.createCollection('API', description: 'd');
      repo.updateCollection(c.copyWith(
        name: 'API v2',
        variables: <Variable>[
          const Variable(id: 'v1', key: 'a', value: 'plain'),
          const Variable(id: 'v2', key: 'b', value: 'secretvalue', secret: true),
        ],
      ));
      final list = repo.listCollections();
      expect(list.single.name, 'API v2');
      expect(list.single.variables.length, 2);
      // Secret values never reach the database.
      final raw = db.db.select('SELECT vars_json FROM collections').first['vars_json'] as String;
      expect(raw.contains('secretvalue'), isFalse);
      expect(repo.deleteCollection(c.id), isEmpty);
      expect(repo.listCollections(), isEmpty);
    });

    test('nested folders and requests keep order', () {
      final c = repo.createCollection('C');
      final f = repo.createFolder(collectionId: c.id, name: 'F');
      final r1 = repo.createRequest(collectionId: c.id, parentId: f.id, request: req('r1', 'one'));
      final r2 = repo.createRequest(collectionId: c.id, parentId: f.id, request: req('r2', 'two'));
      repo.createRequest(collectionId: c.id, request: req('r3', 'top'));
      final nodes = repo.listNodes();
      expect(nodes.length, 4);
      expect(nodes.where((n) => n.parentId == f.id).map((n) => n.id), <String>[r1.id, r2.id]);
      expect(nodes.firstWhere((n) => n.id == 'r1').request!.url, 'https://a.test/one');
    });

    test('moveNode reorders, reparents and rejects cycles', () {
      final c = repo.createCollection('C');
      final a = repo.createFolder(collectionId: c.id, name: 'A');
      final b = repo.createFolder(collectionId: c.id, parentId: a.id, name: 'B');
      repo.createRequest(collectionId: c.id, parentId: a.id, request: req('r1', 'x'));
      repo.createRequest(collectionId: c.id, parentId: a.id, request: req('r2', 'y'));

      repo.moveNode('r2', collectionId: c.id, newParentId: a.id, index: 0);
      final order = repo.listNodes().where((n) => n.parentId == a.id).toList()
        ..sort((x, y) => x.sort.compareTo(y.sort));
      expect(order.first.id, 'r2');

      expect(() => repo.moveNode(a.id, collectionId: c.id, newParentId: b.id), throwsArgumentError);
      expect(() => repo.moveNode(a.id, collectionId: c.id, newParentId: a.id), throwsArgumentError);

      repo.moveNode('r1', collectionId: c.id, newParentId: null);
      expect(repo.listNodes().firstWhere((n) => n.id == 'r1').parentId, isNull);
    });

    test('moving a folder to another collection moves its subtree', () {
      final c1 = repo.createCollection('One');
      final c2 = repo.createCollection('Two');
      final f = repo.createFolder(collectionId: c1.id, name: 'F');
      repo.createRequest(collectionId: c1.id, parentId: f.id, request: req('r1', 'x'));
      repo.moveNode(f.id, collectionId: c2.id, newParentId: null);
      expect(repo.listNodes().every((n) => n.collectionId == c2.id), isTrue);
    });

    test('duplicate copies the subtree with new ids and returns request id map', () {
      final c = repo.createCollection('C');
      final f = repo.createFolder(collectionId: c.id, name: 'F');
      repo.createRequest(collectionId: c.id, parentId: f.id, request: req('r1', 'x'));
      final map = repo.duplicateNode(f.id, nameSuffix: ' copy');
      expect(map.keys, <String>['r1']);
      expect(map['r1'], isNot('r1'));
      final nodes = repo.listNodes();
      expect(nodes.length, 4);
      final copy = nodes.firstWhere((n) => n.isFolder && n.id != f.id);
      expect(copy.name, 'F copy');
      final copiedReq = nodes.firstWhere((n) => n.id == map['r1']);
      expect(copiedReq.parentId, copy.id);
      expect(copiedReq.request!.id, map['r1']);
    });

    test('deleteNode cascades and reports removed request ids', () {
      final c = repo.createCollection('C');
      final f = repo.createFolder(collectionId: c.id, name: 'F');
      repo.createRequest(collectionId: c.id, parentId: f.id, request: req('r1', 'x'));
      repo.createRequest(collectionId: c.id, request: req('r2', 'y'));
      expect(repo.deleteNode(f.id), <String>['r1']);
      expect(repo.listNodes().map((n) => n.id), <String>['r2']);
    });

    test('deleteCollection reports request ids', () {
      final c = repo.createCollection('C');
      repo.createRequest(collectionId: c.id, request: req('r1', 'x'));
      expect(repo.deleteCollection(c.id), <String>['r1']);
      expect(repo.listNodes(), isEmpty);
    });

    test('favorites, rename and save', () {
      final c = repo.createCollection('C');
      repo.createRequest(collectionId: c.id, request: req('r1', 'x'));
      repo.setFavorite('r1', true);
      repo.touchOpened('r1');
      repo.renameNode('r1', 'Renamed');
      repo.saveRequest('r1', req('r1', 'x').copyWith(url: 'https://b.test', name: 'Renamed'));
      final n = repo.listNodes().single;
      expect(n.favorite, isTrue);
      expect(n.lastOpened, isNotNull);
      expect(n.name, 'Renamed');
      expect(n.request!.url, 'https://b.test');
    });

    test('request secrets are never stored in the node JSON', () {
      final c = repo.createCollection('C');
      final r = req('r1', 'x').copyWith(auth: const AuthConfig(type: AuthType.bearer, token: 'TOPSECRET'));
      repo.createRequest(collectionId: c.id, request: r);
      final raw = db.db.select('SELECT data_json FROM nodes').first['data_json'] as String;
      expect(raw.contains('TOPSECRET'), isFalse);
      expect(jsonDecode(raw)['auth']['type'], 'bearer');
    });

    test('runInTransaction rolls everything back on error', () {
      expect(
        () => repo.runInTransaction<void>(() {
          repo.createCollection('A');
          repo.createCollection('B');
          throw StateError('fail');
        }),
        throwsStateError,
      );
      expect(repo.listCollections(), isEmpty);
    });
  });

  group('history', () {
    late SqliteHistoryRepository history;
    setUp(() => history = SqliteHistoryRepository(db));

    HistoryEntry entry(String id, String url, {int? ts, int status = 200}) => HistoryEntry(
          id: id,
          ts: ts ?? DateTime.now().millisecondsSinceEpoch,
          method: 'GET',
          url: url,
          status: status,
        );

    test('add, list newest first, delete, clear', () {
      history.add(entry('a', 'https://a.test', ts: 1000));
      history.add(entry('b', 'https://b.test', ts: 2000));
      expect(history.list().map((e) => e.id), <String>['b', 'a']);
      history.delete('b');
      expect(history.count(), 1);
      history.clear();
      expect(history.count(), 0);
    });

    test('search treats LIKE wildcards literally', () {
      history.add(entry('a', 'https://a.test/100%_done'));
      history.add(entry('b', 'https://b.test/other'));
      expect(history.list(query: '100%').map((e) => e.id), <String>['a']);
      expect(history.list(query: '_done').map((e) => e.id), <String>['a']);
      expect(history.list(query: 'b.test').map((e) => e.id), <String>['b']);
      expect(history.list(query: 'get').length, 2);
    });

    test('prune by count and by age', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 5; i++) {
        history.add(entry('n$i', 'https://x.test/$i', ts: now - i * 1000));
      }
      history.add(entry('old', 'https://old.test', ts: now - const Duration(days: 40).inMilliseconds));
      expect(history.prune(maxAgeDays: 30, maxEntries: 100), 1);
      expect(history.count(), 5);
      expect(history.prune(maxAgeDays: 0, maxEntries: 3), 2);
      expect(history.list().map((e) => e.id), <String>['n0', 'n1', 'n2']);
    });
  });

  group('environments', () {
    late SqliteEnvironmentRepository envs;
    setUp(() => envs = SqliteEnvironmentRepository(db));

    test('save, update, list, active and delete', () {
      const e = Environment(id: 'e1', name: 'Dev', variables: <Variable>[
        Variable(id: 'v1', key: 'host', value: 'localhost'),
        Variable(id: 'v2', key: 'tok', value: 'SECRET', secret: true),
      ]);
      envs.save(e);
      envs.save(e.copyWith(name: 'Development'));
      envs.setActive('e1');
      final list = envs.list();
      expect(list.single.name, 'Development');
      expect(list.single.variables.firstWhere((v) => v.key == 'tok').value, '');
      expect(envs.activeId(), 'e1');
      envs.delete('e1');
      expect(envs.list(), isEmpty);
      expect(envs.activeId(), isNull);
    });

    test('globals', () {
      expect(envs.globals(), isEmpty);
      envs.saveGlobals(const <Variable>[Variable(id: 'g', key: 'k', value: 'v')]);
      expect(envs.globals().single.value, 'v');
    });
  });

  test('clearAllData empties every table', () {
    final c = repo.createCollection('C');
    repo.createRequest(collectionId: c.id, request: req('r1', 'x'));
    SqliteHistoryRepository(db).add(HistoryEntry(id: 'h', ts: 1, method: 'GET', url: 'u'));
    SqliteEnvironmentRepository(db).saveGlobals(const <Variable>[Variable(id: 'g', key: 'k')]);
    db.clearAllData();
    expect(repo.listCollections(), isEmpty);
    expect(repo.listNodes(), isEmpty);
    expect(SqliteHistoryRepository(db).count(), 0);
    expect(SqliteEnvironmentRepository(db).globals(), isEmpty);
  });
}
