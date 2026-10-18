import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../features/environments/domain/variables.dart';

enum CodeLanguage { json, text, xml }

/// Above this size syntax highlighting is skipped to keep typing responsive.
const int kHighlightLimit = 300000;

const int _kDefault = 0;
const int _kKey = 1;
const int _kString = 2;
const int _kNumber = 3;
const int _kLiteral = 4;
const int _kPunct = 5;
const int _kVariable = 6;

const int flagBracket = 1;
const int flagError = 2;
const int flagMatch = 4;
const int flagCurrentMatch = 8;

void _fill(Uint8List a, int s, int e, int v) {
  final end = e > a.length ? a.length : e;
  for (var i = s < 0 ? 0 : s; i < end; i++) {
    a[i] = v;
  }
}

void _scanJson(String t, Uint8List kind) {
  final n = t.length;
  var i = 0;
  bool isDigit(int c) => c >= 48 && c <= 57;
  bool isAlpha(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
  while (i < n) {
    final c = t.codeUnitAt(i);
    if (c == 34) {
      var j = i + 1;
      while (j < n) {
        final d = t.codeUnitAt(j);
        if (d == 92) {
          j += 2;
        } else if (d == 34 || d == 10) {
          break;
        } else {
          j++;
        }
      }
      if (j > n) j = n;
      final closed = j < n && t.codeUnitAt(j) == 34;
      final end = closed ? j + 1 : j;
      var k = end;
      while (k < n && (t.codeUnitAt(k) == 32 || t.codeUnitAt(k) == 9)) {
        k++;
      }
      final isKey = k < n && t.codeUnitAt(k) == 58;
      _fill(kind, i, end, isKey ? _kKey : _kString);
      i = end;
    } else if (isDigit(c) || (c == 45 && i + 1 < n && isDigit(t.codeUnitAt(i + 1)))) {
      var j = i + 1;
      while (j < n) {
        final d = t.codeUnitAt(j);
        if (isDigit(d) || d == 46 || d == 101 || d == 69 || d == 43 || d == 45) {
          j++;
        } else {
          break;
        }
      }
      _fill(kind, i, j, _kNumber);
      i = j;
    } else if (isAlpha(c)) {
      var j = i + 1;
      while (j < n && isAlpha(t.codeUnitAt(j))) {
        j++;
      }
      final w = t.substring(i, j);
      if (w == 'true' || w == 'false' || w == 'null') _fill(kind, i, j, _kLiteral);
      i = j;
    } else if (c == 123 || c == 125 || c == 91 || c == 93 || c == 44 || c == 58) {
      kind[i] = _kPunct;
      i++;
    } else {
      i++;
    }
  }
}

final RegExp _xmlComment = RegExp(r'<!--[\s\S]*?-->');
final RegExp _xmlTag = RegExp(r'<[^<>]*>');
final RegExp _xmlName = RegExp(r'^</?[A-Za-z_!?][\w:.\-]*');
final RegExp _xmlString = RegExp(r'"[^"]*"|' "'[^']*'");
final RegExp _xmlAttr = RegExp(r'\s([\w:.\-]+)=');

void _scanXml(String t, Uint8List kind) {
  for (final m in _xmlComment.allMatches(t)) {
    _fill(kind, m.start, m.end, _kPunct);
  }
  for (final m in _xmlTag.allMatches(t)) {
    if (kind[m.start] == _kPunct && t.startsWith('<!--', m.start)) continue;
    final s = m.group(0)!;
    _fill(kind, m.start, m.end, _kPunct);
    final name = _xmlName.firstMatch(s);
    if (name != null) _fill(kind, m.start, m.start + name.end, _kKey);
    for (final a in _xmlAttr.allMatches(s)) {
      _fill(kind, m.start + a.start + 1, m.start + a.end - 1, _kNumber);
    }
    for (final q in _xmlString.allMatches(s)) {
      _fill(kind, m.start + q.start, m.start + q.end, _kString);
    }
  }
}

/// Finds the bracket matching the one next to [caret]. Returns (a, b) offsets.
(int, int)? findBracketPair(String t, int caret, {bool skipStrings = true}) {
  const open = '{[(';
  const close = '}])';
  final n = t.length;
  if (n == 0 || n > kHighlightLimit) return null;
  int? idx;
  if (caret > 0 && caret <= n && (open.contains(t[caret - 1]) || close.contains(t[caret - 1]))) {
    idx = caret - 1;
  } else if (caret >= 0 && caret < n && (open.contains(t[caret]) || close.contains(t[caret]))) {
    idx = caret;
  }
  if (idx == null) return null;

  Uint8List? inStr;
  if (skipStrings) {
    inStr = Uint8List(n);
    var i = 0;
    while (i < n) {
      if (t.codeUnitAt(i) == 34) {
        var j = i + 1;
        while (j < n && t.codeUnitAt(j) != 34 && t.codeUnitAt(j) != 10) {
          j += t.codeUnitAt(j) == 92 ? 2 : 1;
        }
        final end = j < n ? j + 1 : n;
        _fill(inStr, i, end, 1);
        i = end;
      } else {
        i++;
      }
    }
    if (inStr[idx] == 1) return null;
  }

  final ch = t[idx];
  final isOpen = open.contains(ch);
  final other = isOpen ? close[open.indexOf(ch)] : open[close.indexOf(ch)];
  var depth = 0;
  final step = isOpen ? 1 : -1;
  var i = idx;
  var scanned = 0;
  while (i >= 0 && i < n && scanned < 200000) {
    if (inStr == null || inStr[i] == 0) {
      final c = t[i];
      if (c == ch) depth++;
      if (c == other) {
        depth--;
        if (depth == 0) return (idx, i);
      }
    }
    i += step;
    scanned++;
  }
  return null;
}

/// Builds the highlighted spans. The concatenated span text always equals
/// [text] exactly, which Flutter's text fields require.
TextSpan buildHighlightedSpan({
  required String text,
  required CodeLanguage language,
  required PostBoxColors colors,
  required TextStyle base,
  bool variables = true,
  int? errorOffset,
  (int, int)? bracketPair,
  List<TextRange> matches = const <TextRange>[],
  int currentMatch = -1,
}) {
  final n = text.length;
  if (n == 0) return TextSpan(style: base, text: '');
  final kind = Uint8List(n);
  final flags = Uint8List(n);

  switch (language) {
    case CodeLanguage.json:
      _scanJson(text, kind);
    case CodeLanguage.xml:
      _scanXml(text, kind);
    case CodeLanguage.text:
      break;
  }
  if (variables) {
    for (final m in kVariablePattern.allMatches(text)) {
      _fill(kind, m.start, m.end, _kVariable);
    }
  }
  if (bracketPair != null) {
    flags[bracketPair.$1] |= flagBracket;
    flags[bracketPair.$2] |= flagBracket;
  }
  for (var k = 0; k < matches.length; k++) {
    final m = matches[k];
    final f = k == currentMatch ? flagCurrentMatch : flagMatch;
    for (var i = m.start; i < m.end && i < n; i++) {
      flags[i] |= f;
    }
  }
  if (errorOffset != null && errorOffset >= 0 && errorOffset < n) {
    flags[errorOffset] |= flagError;
  } else if (errorOffset != null && errorOffset >= n && n > 0) {
    flags[n - 1] |= flagError;
  }

  final styles = <int, TextStyle>{};
  TextStyle styleFor(int k, int f) {
    return styles.putIfAbsent(k * 16 + f, () {
      Color? color;
      switch (k) {
        case _kKey:
          color = colors.synKey;
        case _kString:
          color = colors.synString;
        case _kNumber:
          color = colors.synNumber;
        case _kLiteral:
          color = colors.synLiteral;
        case _kPunct:
          color = colors.synPunct;
        case _kVariable:
          color = colors.synVariable;
        default:
          color = null;
      }
      Color? bg;
      if (f & flagCurrentMatch != 0) {
        bg = colors.accent.withAlpha(120);
      } else if (f & flagMatch != 0) {
        bg = colors.accent.withAlpha(55);
      } else if (f & flagBracket != 0) {
        bg = colors.textSecondary.withAlpha(70);
      }
      final err = f & flagError != 0;
      return base.copyWith(
        color: color,
        backgroundColor: bg,
        fontWeight: k == _kVariable ? FontWeight.w600 : null,
        decoration: err ? TextDecoration.underline : null,
        decorationStyle: err ? TextDecorationStyle.wavy : null,
        decorationColor: err ? colors.synError : null,
      );
    });
  }

  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= n; i++) {
    if (i == n || kind[i] != kind[start] || flags[i] != flags[start]) {
      spans.add(TextSpan(text: text.substring(start, i), style: styleFor(kind[start], flags[start])));
      start = i;
    }
  }
  return TextSpan(style: base, children: spans);
}
