import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import 'highlighter.dart';

/// Text controller that paints syntax highlighting, variable highlighting,
/// bracket matching, error underline and find matches.
class CodeEditorController extends TextEditingController {
  CodeEditorController({super.text, CodeLanguage language = CodeLanguage.json})
      : _language = language;

  CodeLanguage _language;
  bool _variables = true;
  int? _errorOffset;
  List<TextRange> _matches = const <TextRange>[];
  int _current = -1;

  // Span cache.
  TextSpan? _span;
  String? _spanText;
  int _spanCaret = -2;
  Object? _spanKey;

  CodeLanguage get language => _language;
  /// No notification on purpose: this is set while the owning widget updates
  /// (during build) and the field repaints from that rebuild anyway.
  set language(CodeLanguage v) => _language = v;

  bool get highlightVariables => _variables;
  set highlightVariables(bool v) => _variables = v;

  int? get errorOffset => _errorOffset;
  List<TextRange> get matches => _matches;
  int get currentMatch => _current;

  void setError(int? offset) {
    if (offset == _errorOffset) return;
    _errorOffset = offset;
    notifyListeners();
  }

  void setMatches(List<TextRange> matches, int current) {
    _matches = matches;
    _current = current;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final comp = value.composing;
    if (withComposing && comp.isValid && !comp.isCollapsed) {
      // Keep IME composition underlines intact; highlighting resumes after.
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final base = style ?? context.codeStyle;
    final t = text;
    if (t.length > kHighlightLimit) return TextSpan(style: base, text: t);
    final c = context.colors;
    final caret = selection.isValid && selection.isCollapsed ? selection.baseOffset : -1;
    final key = Object.hash(_language, _variables, _errorOffset, _current, identityHashCode(_matches), c, base);
    if (_span != null && _spanText == t && _spanCaret == caret && _spanKey == key) {
      return _span!;
    }
    final pair = caret >= 0
        ? findBracketPair(t, caret, skipStrings: _language == CodeLanguage.json)
        : null;
    final span = buildHighlightedSpan(
      text: t,
      language: _language,
      colors: c,
      base: base,
      variables: _variables,
      errorOffset: _errorOffset,
      bracketPair: pair,
      matches: _matches,
      currentMatch: _current,
    );
    _span = span;
    _spanText = t;
    _spanCaret = caret;
    _spanKey = key;
    return span;
  }
}
