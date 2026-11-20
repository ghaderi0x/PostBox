import '../../persistence/app_database.dart';
import '../domain/cookie_jar.dart';

/// Stores the cookie jar in the `cookies` table. Cookie values are not
/// secrets in the sense of this app's vault (they are session identifiers the
/// server handed out); they stay in the local database and are removed by
/// "Clear local data". They are never exported.
class SqliteCookiePersistence implements CookiePersistence {
  SqliteCookiePersistence(this._app);

  final AppDatabase _app;

  @override
  List<StoredCookie> load() => _app.db
      .select('SELECT * FROM cookies')
      .map(
        (r) => StoredCookie(
          domain: r['domain'] as String,
          path: r['path'] as String,
          name: r['name'] as String,
          value: r['value'] as String,
          hostOnly: (r['host_only'] as int) == 1,
          secure: (r['secure'] as int) == 1,
          httpOnly: (r['http_only'] as int) == 1,
          sameSite: r['same_site'] as String,
          expires: r['expires'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  r['expires'] as int,
                  isUtc: true,
                ),
          created: DateTime.fromMillisecondsSinceEpoch(
            r['created'] as int,
            isUtc: true,
          ),
        ),
      )
      .toList();

  @override
  void upsert(StoredCookie c) {
    _app.db.execute(
      'INSERT OR REPLACE INTO cookies(domain,path,name,value,host_only,secure,http_only,same_site,expires,created) '
      'VALUES(?,?,?,?,?,?,?,?,?,?)',
      <Object?>[
        c.domain,
        c.path,
        c.name,
        c.value,
        c.hostOnly ? 1 : 0,
        c.secure ? 1 : 0,
        c.httpOnly ? 1 : 0,
        c.sameSite,
        c.expires?.millisecondsSinceEpoch,
        c.created.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  void remove(StoredCookie c) {
    _app.db.execute(
      'DELETE FROM cookies WHERE domain=? AND path=? AND name=?',
      <Object?>[c.domain, c.path, c.name],
    );
  }

  @override
  void clear() => _app.db.execute('DELETE FROM cookies');
}
