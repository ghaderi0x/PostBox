import '../../persistence/app_database.dart';
import '../domain/history_models.dart';

abstract interface class HistoryRepository {
  void add(HistoryEntry e);
  List<HistoryEntry> list({String query = '', int limit = 200, int offset = 0});
  void delete(String id);
  void clear();
  int count();

  /// Removes entries older than [maxAgeDays] (0 = no age limit) and keeps at
  /// most [maxEntries] newest. Returns how many rows were deleted.
  int prune({required int maxAgeDays, required int maxEntries});
}

class SqliteHistoryRepository implements HistoryRepository {
  SqliteHistoryRepository(this._app);

  final AppDatabase _app;

  @override
  void add(HistoryEntry e) {
    _app.db.execute(
      'INSERT INTO history(id,ts,method,url,status,duration_ms,size,error,request_json) VALUES(?,?,?,?,?,?,?,?,?)',
      <Object?>[e.id, e.ts, e.method, e.url, e.status, e.durationMs, e.size, e.error, e.requestJson],
    );
  }

  @override
  List<HistoryEntry> list({String query = '', int limit = 200, int offset = 0}) {
    final q = query.trim();
    final rows = q.isEmpty
        ? _app.db.select(
            'SELECT * FROM history ORDER BY ts DESC LIMIT ? OFFSET ?',
            <Object?>[limit, offset])
        : _app.db.select(
            r"SELECT * FROM history WHERE url LIKE ? ESCAPE '\' OR method LIKE ? ESCAPE '\' "
            'ORDER BY ts DESC LIMIT ? OFFSET ?',
            <Object?>[_like(q), _like(q), limit, offset]);
    return rows
        .map((r) => HistoryEntry(
              id: r['id'] as String,
              ts: r['ts'] as int,
              method: r['method'] as String,
              url: r['url'] as String,
              status: r['status'] as int?,
              durationMs: r['duration_ms'] as int?,
              size: r['size'] as int?,
              error: r['error'] as String?,
              requestJson: r['request_json'] as String?,
            ))
        .toList();
  }

  String _like(String q) {
    final escaped = q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    return '%$escaped%';
  }

  @override
  void delete(String id) =>
      _app.db.execute('DELETE FROM history WHERE id=?', <Object?>[id]);

  @override
  void clear() => _app.db.execute('DELETE FROM history');

  @override
  int count() => _app.db.select('SELECT COUNT(*) AS n FROM history').first['n'] as int;

  @override
  int prune({required int maxAgeDays, required int maxEntries}) {
    return _app.transaction<int>(() {
      final before = count();
      if (maxAgeDays > 0) {
        final cutoff = DateTime.now()
            .subtract(Duration(days: maxAgeDays))
            .millisecondsSinceEpoch;
        _app.db.execute('DELETE FROM history WHERE ts < ?', <Object?>[cutoff]);
      }
      _app.db.execute(
        'DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY ts DESC LIMIT ?)',
        <Object?>[maxEntries],
      );
      return before - count();
    });
  }
}
