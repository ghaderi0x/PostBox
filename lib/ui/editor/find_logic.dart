import 'package:flutter/material.dart';

/// Finds all matches of [query] in [text]. Throws [FormatException] for an
/// invalid regular expression. Empty matches are skipped.
List<TextRange> findMatches(
  String text,
  String query, {
  bool regex = false,
  bool caseSensitive = false,
  int limit = 5000,
}) {
  if (query.isEmpty) return const <TextRange>[];
  final out = <TextRange>[];
  final re = RegExp(
    regex ? query : RegExp.escape(query),
    caseSensitive: caseSensitive,
    multiLine: true,
  );
  for (final m in re.allMatches(text)) {
    if (m.end == m.start) continue;
    out.add(TextRange(start: m.start, end: m.end));
    if (out.length >= limit) break;
  }
  return out;
}

String _expand(Match m, String replacement) =>
    replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) {
      final i = int.parse(g[1]!);
      return i <= m.groupCount ? (m.group(i) ?? '') : g[0]!;
    });

/// Replaces every match. In regex mode `$1`..`$9` refer to groups.
String replaceAllMatches(
  String text,
  String query,
  String replacement, {
  bool regex = false,
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return text;
  final re = RegExp(
    regex ? query : RegExp.escape(query),
    caseSensitive: caseSensitive,
    multiLine: true,
  );
  return text.replaceAllMapped(re, (m) => m.end == m.start ? m[0]! : (regex ? _expand(m, replacement) : replacement));
}

/// Replaces the single match covering [range].
String replaceOne(
  String text,
  TextRange range,
  String query,
  String replacement, {
  bool regex = false,
  bool caseSensitive = false,
}) {
  final matched = text.substring(range.start, range.end);
  var rep = replacement;
  if (regex) {
    final re = RegExp(query, caseSensitive: caseSensitive, multiLine: true);
    final m = re.matchAsPrefix(text, range.start);
    if (m != null) rep = _expand(m, replacement);
  }
  return text.replaceRange(range.start, range.end, matched.isEmpty ? matched : rep);
}
