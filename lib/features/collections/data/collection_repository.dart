import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../../core/util/ids.dart';
import '../../environments/domain/variables.dart';
import '../../persistence/app_database.dart';
import '../../requests/domain/request_models.dart';
import '../domain/collection_models.dart';
import '../domain/node_settings.dart';
import '../../../core/util/json_util.dart';

abstract interface class CollectionRepository {
  /// Runs [body] atomically; any exception rolls everything back.
  T runInTransaction<T>(T Function() body);

  List<CollectionRecord> listCollections();
  CollectionRecord createCollection(String name, {String description = ''});
  void updateCollection(CollectionRecord c);

  /// Returns ids of all request nodes that were removed with it.
  List<String> deleteCollection(String id);

  List<NodeRecord> listNodes();
  NodeRecord createFolder({
    required String collectionId,
    String? parentId,
    required String name,
  });

  /// The node id equals `request.id`.
  NodeRecord createRequest({
    required String collectionId,
    String? parentId,
    required RequestModel request,
  });
  void saveRequest(String nodeId, RequestModel request);

  /// Saves inherited settings of a folder.
  void saveNodeSettings(String nodeId, NodeSettings settings);
  void renameNode(String id, String name);
  void setNodeDescription(String id, String description);
  void setFavorite(String id, bool favorite);
  void touchOpened(String id);
  void moveNode(
    String id, {
    required String collectionId,
    required String? newParentId,
    int? index,
  });
  void reorder(String collectionId, String? parentId, List<String> orderedIds);

  /// Maps old node ids to new ones for every copied node (folders too).
  Map<String, String> duplicateNode(String id, {String nameSuffix = ' copy'});

  /// Returns ids of all request nodes that were removed.
  List<String> deleteNode(String id);
  void reorderCollections(List<String> orderedIds);
}

class SqliteCollectionRepository implements CollectionRepository {
  SqliteCollectionRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  T runInTransaction<T>(T Function() body) => _app.transaction<T>(body);

  @override
  List<CollectionRecord> listCollections() {
    final rows = _db.select('SELECT * FROM collections ORDER BY sort, created');
    return rows
        .map(
          (r) => CollectionRecord(
            id: r['id'] as String,
            name: r['name'] as String,
            description: r['description'] as String,
            sort: r['sort'] as int,
            variables: _decodeVars(r['vars_json'] as String),
            settings: _decodeSettings(r['settings_json'] as String),
          ),
        )
        .toList();
  }

  NodeSettings _decodeSettings(String json) {
    try {
      return NodeSettings.fromJson(jsonDecode(json));
    } on FormatException {
      return NodeSettings.empty;
    }
  }

  List<Variable> _decodeVars(String json) {
    try {
      return Variable.listFromJson(jsonDecode(json));
    } on FormatException {
      return const <Variable>[];
    }
  }

  @override
  CollectionRecord createCollection(String name, {String description = ''}) {
    final id = newId();
    final now = _now();
    final next =
        (_db
                .select(
                  'SELECT COALESCE(MAX(sort), -1) + 1 AS n FROM collections',
                )
                .first['n']
            as int);
    _db.execute(
      'INSERT INTO collections(id,name,description,sort,vars_json,created,updated) VALUES(?,?,?,?,?,?,?)',
      <Object?>[id, name, description, next, '[]', now, now],
    );
    return CollectionRecord(
      id: id,
      name: name,
      description: description,
      sort: next,
    );
  }

  @override
  void updateCollection(CollectionRecord c) {
    _db.execute(
      'UPDATE collections SET name=?, description=?, vars_json=?, settings_json=?, updated=? WHERE id=?',
      <Object?>[
        c.name,
        c.description,
        jsonEncode(c.variables.map((v) => v.toJson()).toList()),
        jsonEncode(c.settings.toJson()),
        _now(),
        c.id,
      ],
    );
  }

  @override
  List<String> deleteCollection(String id) {
    return _app.transaction<List<String>>(() {
      final removed = _db
          .select(
            "SELECT id FROM nodes WHERE collection_id=? AND kind='request'",
            <Object?>[id],
          )
          .map((r) => r['id'] as String)
          .toList();
      _db.execute('DELETE FROM collections WHERE id=?', <Object?>[id]);
      return removed;
    });
  }

  @override
  void reorderCollections(List<String> orderedIds) {
    _app.transaction<void>(() {
      for (var i = 0; i < orderedIds.length; i++) {
        _db.execute('UPDATE collections SET sort=? WHERE id=?', <Object?>[
          i,
          orderedIds[i],
        ]);
      }
    });
  }

  NodeRecord _nodeFromRow(Row r) {
    final kind = r['kind'] == 'folder' ? NodeKind.folder : NodeKind.request;
    RequestModel? req;
    final data = r['data_json'];
    if (kind == NodeKind.request && data is String) {
      try {
        req = RequestModel.fromJson(
          jsonDecode(data),
        ).copyWith(id: r['id'] as String);
      } on FormatException {
        req = RequestModel(id: r['id'] as String, name: r['name'] as String);
      }
    }
    return NodeRecord(
      id: r['id'] as String,
      collectionId: r['collection_id'] as String,
      parentId: r['parent_id'] as String?,
      kind: kind,
      name: r['name'] as String,
      description: r['description'] as String,
      sort: r['sort'] as int,
      favorite: (r['favorite'] as int) == 1,
      lastOpened: r['last_opened'] as int?,
      request: req,
      settings: kind == NodeKind.folder
          ? _decodeSettings(r['settings_json'] as String)
          : NodeSettings.empty,
    );
  }

  @override
  List<NodeRecord> listNodes() => _db
      .select(
        'SELECT * FROM nodes ORDER BY collection_id, parent_id, sort, created',
      )
      .map(_nodeFromRow)
      .toList();

  NodeRecord _getNode(String id) => _nodeFromRow(
    _db.select('SELECT * FROM nodes WHERE id=?', <Object?>[id]).first,
  );

  int _nextSort(String collectionId, String? parentId) {
    final rs = parentId == null
        ? _db.select(
            'SELECT COALESCE(MAX(sort), -1) + 1 AS n FROM nodes WHERE collection_id=? AND parent_id IS NULL',
            <Object?>[collectionId],
          )
        : _db.select(
            'SELECT COALESCE(MAX(sort), -1) + 1 AS n FROM nodes WHERE collection_id=? AND parent_id=?',
            <Object?>[collectionId, parentId],
          );
    return rs.first['n'] as int;
  }

  @override
  NodeRecord createFolder({
    required String collectionId,
    String? parentId,
    required String name,
  }) {
    final id = newId();
    final now = _now();
    _db.execute(
      "INSERT INTO nodes(id,collection_id,parent_id,kind,name,sort,created,updated) VALUES(?,?,?,'folder',?,?,?,?)",
      <Object?>[
        id,
        collectionId,
        parentId,
        name,
        _nextSort(collectionId, parentId),
        now,
        now,
      ],
    );
    return _getNode(id);
  }

  @override
  NodeRecord createRequest({
    required String collectionId,
    String? parentId,
    required RequestModel request,
  }) {
    final now = _now();
    _db.execute(
      "INSERT INTO nodes(id,collection_id,parent_id,kind,name,sort,data_json,created,updated) VALUES(?,?,?,'request',?,?,?,?,?)",
      <Object?>[
        request.id,
        collectionId,
        parentId,
        request.displayName.isEmpty ? 'Request' : request.displayName,
        _nextSort(collectionId, parentId),
        jsonEncode(request.toJson()),
        now,
        now,
      ],
    );
    return _getNode(request.id);
  }

  @override
  void saveRequest(String nodeId, RequestModel request) {
    _db.execute(
      'UPDATE nodes SET name=?, data_json=?, updated=? WHERE id=?',
      <Object?>[
        request.displayName.isEmpty ? 'Request' : request.displayName,
        jsonEncode(request.toJson()),
        _now(),
        nodeId,
      ],
    );
  }

  @override
  void saveNodeSettings(String nodeId, NodeSettings settings) {
    _db.execute(
      'UPDATE nodes SET settings_json=?, updated=? WHERE id=?',
      <Object?>[jsonEncode(settings.toJson()), _now(), nodeId],
    );
  }

  @override
  void renameNode(String id, String name) {
    _app.transaction<void>(() {
      _db.execute('UPDATE nodes SET name=?, updated=? WHERE id=?', <Object?>[
        name,
        _now(),
        id,
      ]);
      final n = _getNode(id);
      if (n.request != null) {
        saveRequestJsonOnly(id, n.request!.copyWith(name: name));
      }
    });
  }

  void saveRequestJsonOnly(String id, RequestModel r) {
    _db.execute('UPDATE nodes SET data_json=? WHERE id=?', <Object?>[
      jsonEncode(r.toJson()),
      id,
    ]);
  }

  @override
  void setNodeDescription(String id, String description) {
    _db.execute(
      'UPDATE nodes SET description=?, updated=? WHERE id=?',
      <Object?>[description, _now(), id],
    );
  }

  @override
  void setFavorite(String id, bool favorite) {
    _db.execute('UPDATE nodes SET favorite=? WHERE id=?', <Object?>[
      favorite ? 1 : 0,
      id,
    ]);
  }

  @override
  void touchOpened(String id) {
    _db.execute('UPDATE nodes SET last_opened=? WHERE id=?', <Object?>[
      _now(),
      id,
    ]);
  }

  List<String> _subtreeIds(String id) => _db
      .select(
        'WITH RECURSIVE d(id) AS (SELECT id FROM nodes WHERE id=? '
        'UNION ALL SELECT n.id FROM nodes n JOIN d ON n.parent_id = d.id) SELECT id FROM d',
        <Object?>[id],
      )
      .map((r) => r['id'] as String)
      .toList();

  List<String> _childIds(String collectionId, String? parentId) {
    final rs = parentId == null
        ? _db.select(
            'SELECT id FROM nodes WHERE collection_id=? AND parent_id IS NULL ORDER BY sort, created',
            <Object?>[collectionId],
          )
        : _db.select(
            'SELECT id FROM nodes WHERE collection_id=? AND parent_id=? ORDER BY sort, created',
            <Object?>[collectionId, parentId],
          );
    return rs.map((r) => r['id'] as String).toList();
  }

  @override
  void moveNode(
    String id, {
    required String collectionId,
    required String? newParentId,
    int? index,
  }) {
    _app.transaction<void>(() {
      final subtree = _subtreeIds(id);
      if (newParentId != null && subtree.contains(newParentId)) {
        throw ArgumentError('Cannot move a folder into itself.');
      }
      _db.execute(
        'UPDATE nodes SET parent_id=?, collection_id=?, updated=? WHERE id=?',
        <Object?>[newParentId, collectionId, _now(), id],
      );
      for (final sid in subtree) {
        _db.execute('UPDATE nodes SET collection_id=? WHERE id=?', <Object?>[
          collectionId,
          sid,
        ]);
      }
      final siblings = _childIds(collectionId, newParentId)..remove(id);
      final at = clampInt(index ?? siblings.length, 0, siblings.length);
      siblings.insert(at, id);
      for (var i = 0; i < siblings.length; i++) {
        _db.execute('UPDATE nodes SET sort=? WHERE id=?', <Object?>[
          i,
          siblings[i],
        ]);
      }
    });
  }

  @override
  void reorder(String collectionId, String? parentId, List<String> orderedIds) {
    _app.transaction<void>(() {
      for (var i = 0; i < orderedIds.length; i++) {
        _db.execute('UPDATE nodes SET sort=? WHERE id=?', <Object?>[
          i,
          orderedIds[i],
        ]);
      }
    });
  }

  @override
  Map<String, String> duplicateNode(String id, {String nameSuffix = ' copy'}) {
    return _app.transaction<Map<String, String>>(() {
      final root = _getNode(id);
      final ids = _subtreeIds(id);
      final nodes = <String, NodeRecord>{for (final i in ids) i: _getNode(i)};
      final idMap = <String, String>{for (final i in ids) i: newId()};
      final now = _now();

      // Parents first: _subtreeIds returns the root first, then breadth-wise.
      for (final oldId in ids) {
        final n = nodes[oldId]!;
        final nid = idMap[oldId]!;
        final isRoot = oldId == id;
        final parent = isRoot ? n.parentId : idMap[n.parentId];
        final name = isRoot ? '${n.name}$nameSuffix' : n.name;
        String? data;
        if (n.request != null) {
          data = jsonEncode(n.request!.copyWith(id: nid, name: name).toJson());
        }
        _db.execute(
          'INSERT INTO nodes(id,collection_id,parent_id,kind,name,description,sort,favorite,data_json,settings_json,created,updated) '
          'VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
          <Object?>[
            nid,
            n.collectionId,
            parent,
            n.isFolder ? 'folder' : 'request',
            name,
            n.description,
            isRoot ? n.sort + 1 : n.sort,
            0,
            data,
            jsonEncode(n.settings.toJson()),
            now,
            now,
          ],
        );
      }
      // Close the gap: re-number siblings keeping the copy right after the original.
      final siblings = _childIds(root.collectionId, root.parentId);
      final copyId = idMap[id]!;
      siblings.remove(copyId);
      final at = siblings.indexOf(id) + 1;
      siblings.insert(at, copyId);
      for (var i = 0; i < siblings.length; i++) {
        _db.execute('UPDATE nodes SET sort=? WHERE id=?', <Object?>[
          i,
          siblings[i],
        ]);
      }
      return idMap;
    });
  }

  @override
  List<String> deleteNode(String id) {
    return _app.transaction<List<String>>(() {
      final removed = <String>[];
      for (final sid in _subtreeIds(id)) {
        final r = _db.select('SELECT kind FROM nodes WHERE id=?', <Object?>[
          sid,
        ]);
        if (r.isNotEmpty && r.first['kind'] == 'request') removed.add(sid);
      }
      _db.execute('DELETE FROM nodes WHERE id=?', <Object?>[id]);
      return removed;
    });
  }
}
