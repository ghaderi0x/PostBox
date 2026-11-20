import '../../persistence/app_database.dart';

/// Small key/value store in the workspace database for the open tabs and the
/// panel layout. It lives next to the collections, so each workspace restores
/// its own session. Contains no secrets (drafts are saved without them).
class SessionStore {
  SessionStore(this._app);

  final AppDatabase _app;

  static const String tabsKey = 'session.tabs';
  static const String layoutKey = 'ui.layout';

  String? read(String key) {
    final rows = _app.db.select('SELECT value FROM kv WHERE key=?', <Object?>[
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void write(String key, String value) {
    _app.db.execute(
      'INSERT OR REPLACE INTO kv(key, value) VALUES(?, ?)',
      <Object?>[key, value],
    );
  }

  void delete(String key) {
    _app.db.execute('DELETE FROM kv WHERE key=?', <Object?>[key]);
  }
}
