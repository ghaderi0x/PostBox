/// Keyboard shortcut model: actions, key combinations and conflict checks.
/// Pure Dart; the mapping to Flutter key events lives in ui/shortcuts.
library;

enum ShortcutAction {
  send,
  save,
  commandPalette,
  newTab,
  closeTab,
  nextTab,
  previousTab,
}

/// A key combination such as `ctrl+shift+k`.
class KeyCombo {
  const KeyCombo(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// Lowercase key name: `a`..`z`, `0`..`9`, `enter`, `tab`, `pageup`,
  /// `pagedown`, `f1`..`f12`, `comma`, `period`, `slash`.
  final String key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  static const Set<String> namedKeys = <String>{
    'enter',
    'tab',
    'space',
    'pageup',
    'pagedown',
    'home',
    'end',
    'comma',
    'period',
    'slash',
    'backslash',
    'bracketleft',
    'bracketright',
    'minus',
    'equal',
  };

  static bool isKnownKey(String k) {
    if (RegExp(r'^[a-z0-9]$').hasMatch(k)) return true;
    if (RegExp(r'^f([1-9]|1[0-2])$').hasMatch(k)) return true;
    return namedKeys.contains(k);
  }

  /// A shortcut must not hijack plain typing: it needs Ctrl, Alt or Meta,
  /// unless it is a function key.
  bool get isValid {
    if (!isKnownKey(key)) return false;
    final fKey = RegExp(r'^f([1-9]|1[0-2])$').hasMatch(key);
    return ctrl || alt || meta || fKey;
  }

  /// Parses `ctrl+shift+k`. Null for anything invalid.
  static KeyCombo? parse(String text) {
    final parts = text
        .toLowerCase()
        .split('+')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    var ctrl = false, shift = false, alt = false, meta = false;
    String? key;
    for (final p in parts) {
      switch (p) {
        case 'ctrl':
        case 'control':
          ctrl = true;
        case 'shift':
          shift = true;
        case 'alt':
          alt = true;
        case 'meta':
        case 'cmd':
        case 'win':
          meta = true;
        default:
          if (key != null) return null;
          key = p;
      }
    }
    if (key == null) return null;
    final combo = KeyCombo(key, ctrl: ctrl, shift: shift, alt: alt, meta: meta);
    return combo.isValid ? combo : null;
  }

  String serialize() => <String>[
    if (ctrl) 'ctrl',
    if (shift) 'shift',
    if (alt) 'alt',
    if (meta) 'meta',
    key,
  ].join('+');

  /// Human readable form, for example `Ctrl+Shift+K`.
  String display() {
    String name() {
      switch (key) {
        case 'pageup':
          return 'PgUp';
        case 'pagedown':
          return 'PgDn';
        case 'comma':
          return ',';
        case 'period':
          return '.';
        case 'slash':
          return '/';
        case 'backslash':
          return '\\';
        case 'bracketleft':
          return '[';
        case 'bracketright':
          return ']';
        case 'minus':
          return '-';
        case 'equal':
          return '=';
      }
      return key.length == 1
          ? key.toUpperCase()
          : key[0].toUpperCase() + key.substring(1);
    }

    return <String>[
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Meta',
      name(),
    ].join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is KeyCombo &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt, meta);
}

const Map<ShortcutAction, KeyCombo> kDefaultShortcuts =
    <ShortcutAction, KeyCombo>{
      ShortcutAction.send: KeyCombo('enter', ctrl: true),
      ShortcutAction.save: KeyCombo('s', ctrl: true),
      ShortcutAction.commandPalette: KeyCombo('k', ctrl: true),
      ShortcutAction.newTab: KeyCombo('t', ctrl: true),
      ShortcutAction.closeTab: KeyCombo('w', ctrl: true),
      ShortcutAction.nextTab: KeyCombo('pagedown', ctrl: true),
      ShortcutAction.previousTab: KeyCombo('pageup', ctrl: true),
    };

/// Defaults overlaid with the user's overrides (stored as action name ->
/// combo text). Invalid or unknown entries are ignored. An override that
/// would give two actions the same combination is ignored too, so the result
/// never binds one key to two actions. (The settings screen already refuses
/// such a choice; this protects against edited or imported settings.)
Map<ShortcutAction, KeyCombo> effectiveShortcuts(
  Map<String, String> overrides,
) {
  final map = <ShortcutAction, KeyCombo>{...kDefaultShortcuts};
  for (final a in ShortcutAction.values) {
    final text = overrides[a.name];
    if (text == null) continue;
    final combo = KeyCombo.parse(text);
    if (combo == null) continue;
    if (findShortcutConflict(map, combo, except: a) != null) continue;
    map[a] = combo;
  }
  return map;
}

/// The action that already uses [combo] (other than [except]), if any.
ShortcutAction? findShortcutConflict(
  Map<ShortcutAction, KeyCombo> current,
  KeyCombo combo, {
  required ShortcutAction except,
}) {
  for (final e in current.entries) {
    if (e.key != except && e.value == combo) return e.key;
  }
  return null;
}
