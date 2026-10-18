import 'package:sqlite3/sqlite3.dart';

import '../../core/util/app_log.dart';

/// SQLite database with versioned, transactional migrations.
///
/// Migrations are append-only: never edit an entry once released, add a new
/// one. `PRAGMA user_version` records how many have been applied.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const List<List<String>> migrations = <List<String>>[
    // v1
    <String>[
      '''
      CREATE TABLE collections(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL DEFAULT 0,
        vars_json TEXT NOT NULL DEFAULT '[]',
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
      )''',
      '''
      CREATE TABLE nodes(
        id TEXT PRIMARY KEY,
        collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
        parent_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
        kind TEXT NOT NULL CHECK(kind IN ('folder','request')),
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        last_opened INTEGER,
        data_json TEXT,
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
      )''',
      'CREATE INDEX idx_nodes_parent ON nodes(collection_id, parent_id, sort)',
      '''
      CREATE TABLE environments(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0,
        vars_json TEXT NOT NULL DEFAULT '[]'
      )''',
      '''
      CREATE TABLE history(
        id TEXT PRIMARY KEY,
        ts INTEGER NOT NULL,
        method TEXT NOT NULL,
        url TEXT NOT NULL,
        status INTEGER,
        duration_ms INTEGER,
        size INTEGER,
        error TEXT,
        request_json TEXT
      )''',
      'CREATE INDEX idx_history_ts ON history(ts DESC)',
      '''
      CREATE TABLE kv(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''',
    ],
  ];

  static int get latestVersion => migrations.length;

  static AppDatabase open(String path, {AppLog? log}) =>
      _init(sqlite3.open(path), log);

  static AppDatabase openInMemory({AppLog? log}) =>
      _init(sqlite3.openInMemory(), log);

  static AppDatabase _init(Database db, AppLog? log) {
    db.execute('PRAGMA foreign_keys = ON');
    final app = AppDatabase._(db);
    app._migrate(log);
    return app;
  }

  int get schemaVersion => db.userVersion;

  /// Opens a database created by an older build and brings it up to date.
  /// Exposed for migration tests.
  static AppDatabase migrateExisting(Database db, {AppLog? log}) =>
      _init(db, log);

  void _migrate(AppLog? log) {
    final current = db.userVersion;
    if (current > migrations.length) {
      throw StateError(
        'Database schema v$current is newer than this app supports (v${migrations.length}).',
      );
    }
    for (var v = current; v < migrations.length; v++) {
      db.execute('BEGIN');
      try {
        for (final sql in migrations[v]) {
          db.execute(sql);
        }
        db.userVersion = v + 1;
        db.execute('COMMIT');
        log?.info('Database migrated to v${v + 1}');
      } on Object {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  /// Runs [body] inside a transaction; rolls back on any error.
  T transaction<T>(T Function() body) {
    db.execute('BEGIN');
    try {
      final r = body();
      db.execute('COMMIT');
      return r;
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Deletes all user data (not the schema).
  void clearAllData() {
    transaction<void>(() {
      db.execute('DELETE FROM nodes');
      db.execute('DELETE FROM collections');
      db.execute('DELETE FROM environments');
      db.execute('DELETE FROM history');
      db.execute('DELETE FROM kv');
    });
  }
}
