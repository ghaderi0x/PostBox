import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../features/shortcuts/shortcut_catalog.dart';

/// Key names used in [KeyCombo] mapped to Flutter keys.
const Map<String, LogicalKeyboardKey> _keys = <String, LogicalKeyboardKey>{
  'a': LogicalKeyboardKey.keyA,
  'b': LogicalKeyboardKey.keyB,
  'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD,
  'e': LogicalKeyboardKey.keyE,
  'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG,
  'h': LogicalKeyboardKey.keyH,
  'i': LogicalKeyboardKey.keyI,
  'j': LogicalKeyboardKey.keyJ,
  'k': LogicalKeyboardKey.keyK,
  'l': LogicalKeyboardKey.keyL,
  'm': LogicalKeyboardKey.keyM,
  'n': LogicalKeyboardKey.keyN,
  'o': LogicalKeyboardKey.keyO,
  'p': LogicalKeyboardKey.keyP,
  'q': LogicalKeyboardKey.keyQ,
  'r': LogicalKeyboardKey.keyR,
  's': LogicalKeyboardKey.keyS,
  't': LogicalKeyboardKey.keyT,
  'u': LogicalKeyboardKey.keyU,
  'v': LogicalKeyboardKey.keyV,
  'w': LogicalKeyboardKey.keyW,
  'x': LogicalKeyboardKey.keyX,
  'y': LogicalKeyboardKey.keyY,
  'z': LogicalKeyboardKey.keyZ,
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
  'f1': LogicalKeyboardKey.f1,
  'f2': LogicalKeyboardKey.f2,
  'f3': LogicalKeyboardKey.f3,
  'f4': LogicalKeyboardKey.f4,
  'f5': LogicalKeyboardKey.f5,
  'f6': LogicalKeyboardKey.f6,
  'f7': LogicalKeyboardKey.f7,
  'f8': LogicalKeyboardKey.f8,
  'f9': LogicalKeyboardKey.f9,
  'f10': LogicalKeyboardKey.f10,
  'f11': LogicalKeyboardKey.f11,
  'f12': LogicalKeyboardKey.f12,
  'enter': LogicalKeyboardKey.enter,
  'tab': LogicalKeyboardKey.tab,
  'space': LogicalKeyboardKey.space,
  'pageup': LogicalKeyboardKey.pageUp,
  'pagedown': LogicalKeyboardKey.pageDown,
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'comma': LogicalKeyboardKey.comma,
  'period': LogicalKeyboardKey.period,
  'slash': LogicalKeyboardKey.slash,
  'backslash': LogicalKeyboardKey.backslash,
  'bracketleft': LogicalKeyboardKey.bracketLeft,
  'bracketright': LogicalKeyboardKey.bracketRight,
  'minus': LogicalKeyboardKey.minus,
  'equal': LogicalKeyboardKey.equal,
};

final Map<LogicalKeyboardKey, String> _names = <LogicalKeyboardKey, String>{
  for (final e in _keys.entries) e.value: e.key,
};

/// The activator Flutter needs to bind [combo]; null for an unknown key.
SingleActivator? activatorFor(KeyCombo combo) {
  final key = _keys[combo.key];
  if (key == null) return null;
  return SingleActivator(
    key,
    control: combo.ctrl,
    shift: combo.shift,
    alt: combo.alt,
    meta: combo.meta,
  );
}

/// Builds a combo from a key press while the user is recording a shortcut.
/// Returns null for modifier-only presses and keys PostBox does not support.
KeyCombo? comboFromEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final name = _names[event.logicalKey];
  if (name == null) return null;
  final kb = HardwareKeyboard.instance;
  return KeyCombo(
    name,
    ctrl: kb.isControlPressed,
    shift: kb.isShiftPressed,
    alt: kb.isAltPressed,
    meta: kb.isMetaPressed,
  );
}
