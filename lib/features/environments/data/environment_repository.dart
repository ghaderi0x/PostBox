import 'dart:convert';

import '../../persistence/app_database.dart';
import '../domain/variables.dart';

abstract interface class EnvironmentRepository {
  /// Variables of secret entries come back with empty values.
  List<Environment> list();
  void save(Environment e);
  void delete(String id);
  String? activeId();
  void setActive(String? id);
  List<Variable> globals();
  void saveGlobals(List<Variable> vars);
}

class SqliteEnvironmentRepository implements EnvironmentRepository {
  SqliteEnvironmentRepository(this._app);

  final AppDatabase _app;

  static const String _activeKey = 'active_environment';
  static const String _globalsKey = 'global_variables';

  String? _kvGet(String key) {
    final rs = _app.db.select('SELECT value FROM kv WHERE key=?', <Object?>[key]);
    return rs.isEmpty ? null : rs.first['value'] as String;
  }

  void _kvSet(String key, String? value) {
    if (value == null) {
      _app.db.execute('DELETE FROM kv WHERE key=?', <Object?>[key]);
    } else {
      _app.db.execute(
        'INSERT INTO kv(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        <Object?>[key, value],
      );
    }
  }

  @override
  List<Environment> list() {
    final rows = _app.db.select('SELECT * FROM environments ORDER BY sort, name');
    return rows.map((r) {
      List<Variable> vars;
      try {
        vars = Variable.listFromJson(jsonDecode(r['vars_json'] as String));
      } on FormatException {
        vars = const <Variable>[];
      }
      return Environment(id: r['id'] as String, name: r['name'] as String, variables: vars);
    }).toList();
  }

  @override
  void save(Environment e) {
    final exists = _app.db.select('SELECT 1 FROM environments WHERE id=?', <Object?>[e.id]).isNotEmpty;
    final vars = jsonEncode(e.variables.map((v) => v.toJson()).toList());
    if (exists) {
      _app.db.execute('UPDATE environments SET name=?, vars_json=? WHERE id=?', <Object?>[e.name, vars, e.id]);
    } else {
      final next = _app.db.select('SELECT COALESCE(MAX(sort), -1) + 1 AS n FROM environments').first['n'] as int;
      _app.db.execute(
        'INSERT INTO environments(id,name,sort,vars_json) VALUES(?,?,?,?)',
        <Object?>[e.id, e.name, next, vars],
      );
    }
  }

  @override
  void delete(String id) {
    _app.transaction<void>(() {
      _app.db.execute('DELETE FROM environments WHERE id=?', <Object?>[id]);
      if (_kvGet(_activeKey) == id) _kvSet(_activeKey, null);
    });
  }

  @override
  String? activeId() => _kvGet(_activeKey);

  @override
  void setActive(String? id) => _kvSet(_activeKey, id);

  @override
  List<Variable> globals() {
    final raw = _kvGet(_globalsKey);
    if (raw == null) return const <Variable>[];
    try {
      return Variable.listFromJson(jsonDecode(raw));
    } on FormatException {
      return const <Variable>[];
    }
  }

  @override
  void saveGlobals(List<Variable> vars) =>
      _kvSet(_globalsKey, jsonEncode(vars.map((v) => v.toJson()).toList()));
}
