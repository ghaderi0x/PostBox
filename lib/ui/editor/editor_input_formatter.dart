import 'package:flutter/services.dart';

import 'highlighter.dart';

/// Auto-indent on Enter and auto-close/skip-over for brackets and quotes.
/// Only acts on a single typed character with a collapsed caret, so pasting
/// and IME composition are never altered.
class EditorInputFormatter extends TextInputFormatter {
  EditorInputFormatter({
    required this.language,
    required this.tabSize,
    required this.autoClose,
  });

  final CodeLanguage language;
  final int tabSize;
  final bool autoClose;

  static const String _openers = '{[(';
  static const String _closers = '}])';

  bool _isWord(String c) => RegExp(r'[\w]').hasMatch(c);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (language == CodeLanguage.text) return newValue;
    final o = oldValue;
    final n = newValue;
    if (!o.selection.isValid ||
        !o.selection.isCollapsed ||
        !n.selection.isCollapsed ||
        n.composing.isValid && !n.composing.isCollapsed ||
        n.text.length != o.text.length + 1 ||
        n.selection.baseOffset != o.selection.baseOffset + 1) {
      return newValue;
    }
    final caret = o.selection.baseOffset;
    final typed = n.text[caret];
    final before = o.text.substring(0, caret);
    final after = o.text.substring(caret);
    final nextChar = after.isEmpty ? '' : after[0];

    if (typed == '\n') {
      final lineStart = before.lastIndexOf('\n') + 1;
      final line = before.substring(lineStart);
      final indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
      final trimmed = line.trimRight();
      final prev = trimmed.isEmpty ? '' : trimmed[trimmed.length - 1];
      final extra =
          (language == CodeLanguage.json && (prev == '{' || prev == '[')) ||
              (language == CodeLanguage.xml && prev == '>' && nextChar != '<')
          ? ' ' * tabSize
          : '';
      final between =
          extra.isNotEmpty &&
          language == CodeLanguage.json &&
          ((prev == '{' && nextChar == '}') ||
              (prev == '[' && nextChar == ']'));
      if (between) {
        final text = '$before\n$indent$extra\n$indent$after';
        final off = caret + 1 + indent.length + extra.length;
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: off),
        );
      }
      final ins = '\n$indent$extra';
      return TextEditingValue(
        text: '$before$ins$after',
        selection: TextSelection.collapsed(offset: caret + ins.length),
      );
    }

    if (language != CodeLanguage.json || !autoClose) return newValue;

    // Typing a closing character right before the same one: step over it.
    if ((_closers.contains(typed) || typed == '"') && nextChar == typed) {
      return TextEditingValue(
        text: o.text,
        selection: TextSelection.collapsed(offset: caret + 1),
      );
    }
    if (_openers.contains(typed)) {
      final close = _closers[_openers.indexOf(typed)];
      return TextEditingValue(
        text: '$before$typed$close$after',
        selection: TextSelection.collapsed(offset: caret + 1),
      );
    }
    if (typed == '"') {
      final prevChar = before.isEmpty ? '' : before[before.length - 1];
      final wordAround =
          (prevChar.isNotEmpty && _isWord(prevChar)) ||
          (nextChar.isNotEmpty && _isWord(nextChar)) ||
          prevChar == '\\';
      if (!wordAround) {
        return TextEditingValue(
          text: '$before""$after',
          selection: TextSelection.collapsed(offset: caret + 1),
        );
      }
    }
    return newValue;
  }
}
