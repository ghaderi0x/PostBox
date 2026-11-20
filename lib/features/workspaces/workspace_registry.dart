import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/util/ids.dart';
import '../../core/util/json_util.dart';

/// One workspace: its own database file with collections, environments,
/// history, cookies and templates. Settings and secrets are shared.
class WorkspaceInfo {
  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.file,
  });

  final String id;
  final String name;

  /// File name inside the app support directory.
  final String file;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'file': file,
  };
}

/// The id of the workspace that existed before workspaces were introduced.
const String kDefaultWorkspaceId = 'default';

/// Keeps the list of workspaces and which one is active.
///
/// Stored in shared preferences under [prefsKey]. The default workspace keeps
/// using `postbox.db`, so upgrading loses nothing.
class WorkspaceRegistry {
  WorkspaceRegistry._(this._prefs, this._items, this._activeId);

  static const String prefsKey = 'workspaces.v1';
  static const int maxWorkspaces = 20;

  final SharedPreferences? _prefs;
  final List<WorkspaceInfo> _items;
  String _activeId;

  static WorkspaceInfo get _default => const WorkspaceInfo(
    id: kDefaultWorkspaceId,
    name: 'Default',
    file: 'postbox.db',
  );

  static Future<WorkspaceRegistry> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromPrefs(prefs);
  }

  static WorkspaceRegistry fromPrefs(SharedPreferences? prefs) {
    final raw = prefs?.getString(prefsKey);
    final items = <WorkspaceInfo>[];
    var active = kDefaultWorkspaceId;
    if (raw != null) {
      try {
        final m = asMap(jsonDecode(raw));
        for (final e in asList(m['items'])) {
          final w = asMap(e);
          final id = asString(w['id']);
          final file = asString(w['file']);
          // Only plain file names: never a path chosen by a stored value.
          if (id.isEmpty ||
              file.isEmpty ||
              file != p.basename(file) ||
              !file.endsWith('.db')) {
            continue;
          }
          items.add(
            WorkspaceInfo(id: id, name: asString(w['name'], id), file: file),
          );
        }
        active = asString(m['active'], kDefaultWorkspaceId);
      } on FormatException {
        // Corrupt value: fall back to the default workspace only.
      }
    }
    if (!items.any((w) => w.id == kDefaultWorkspaceId)) {
      items.insert(0, _default);
    }
    if (!items.any((w) => w.id == active)) active = kDefaultWorkspaceId;
    return WorkspaceRegistry._(prefs, items, active);
  }

  /// For tests: nothing is persisted.
  static WorkspaceRegistry inMemory() => fromPrefs(null);

  List<WorkspaceInfo> get items => List<WorkspaceInfo>.unmodifiable(_items);
  String get activeId => _activeId;
  WorkspaceInfo get active => _items.firstWhere((w) => w.id == _activeId);

  Future<void> _save() async {
    await _prefs?.setString(
      prefsKey,
      jsonEncode(<String, dynamic>{
        'active': _activeId,
        'items': _items.map((w) => w.toJson()).toList(),
      }),
    );
  }

  /// Creates a workspace (the caller decides whether to switch to it).
  Future<WorkspaceInfo> create(String name) async {
    if (_items.length >= maxWorkspaces) {
      throw StateError('At most $maxWorkspaces workspaces.');
    }
    final id = newId();
    final trimmed = name.trim();
    final w = WorkspaceInfo(
      id: id,
      name: trimmed.isEmpty ? 'Workspace ${_items.length + 1}' : trimmed,
      file: 'ws_$id.db',
    );
    _items.add(w);
    await _save();
    return w;
  }

  Future<void> rename(String id, String name) async {
    final i = _items.indexWhere((w) => w.id == id);
    if (i < 0 || name.trim().isEmpty) return;
    _items[i] = WorkspaceInfo(id: id, name: name.trim(), file: _items[i].file);
    await _save();
  }

  Future<void> setActive(String id) async {
    if (!_items.any((w) => w.id == id)) return;
    _activeId = id;
    await _save();
  }

  /// Removes a workspace and deletes its database file in [dir]. The default
  /// and the active workspace cannot be removed.
  Future<bool> remove(String id, {Directory? dir}) async {
    if (id == kDefaultWorkspaceId || id == _activeId) return false;
    final i = _items.indexWhere((w) => w.id == id);
    if (i < 0) return false;
    final w = _items.removeAt(i);
    await _save();
    if (dir != null) {
      for (final suffix in <String>['', '-wal', '-shm', '-journal']) {
        final f = File(p.join(dir.path, '${w.file}$suffix'));
        if (await f.exists()) await f.delete();
      }
    }
    return true;
  }
}

/// Handed to the UI so it can list, create and switch workspaces.
class WorkspaceManager {
  WorkspaceManager({
    required this.registry,
    required this.switchTo,
    required this.directory,
  });

  final WorkspaceRegistry registry;

  /// Closes the current workspace and opens [id].
  final Future<void> Function(String id) switchTo;
  final Directory? directory;

  Future<void> removeWorkspace(String id) =>
      registry.remove(id, dir: directory);
}
