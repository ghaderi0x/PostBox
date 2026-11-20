import 'dart:convert';

import '../../features/environments/domain/variables.dart';
import '../../core/util/json_util.dart';

class JsonProblem {
  const JsonProblem(this.message, this.offset, this.line, this.column);
  final String message;
  final int offset;

  /// 1-based.
  final int line;
  final int column;
}

/// 1-based line and column for [offset].
(int, int) offsetToLineCol(String text, int offset) {
  final o = clampInt(offset, 0, text.length);
  var line = 1;
  var last = -1;
  for (var i = 0; i < o; i++) {
    if (text.codeUnitAt(i) == 10) {
      line++;
      last = i;
    }
  }
  return (line, o - last);
}

/// Replaces `{{var}}` with same-length filler so JSON that uses variables
/// still validates and error offsets stay correct.
String maskVariables(String text) =>
    text.replaceAllMapped(kVariablePattern, (m) => '0'.padRight(m[0]!.length));

JsonProblem? validateJson(String text) {
  if (text.trim().isEmpty) return null;
  try {
    jsonDecode(maskVariables(text));
    return null;
  } on FormatException catch (e) {
    final off = clampInt(e.offset ?? 0, 0, text.length);
    final (line, col) = offsetToLineCol(text, off);
    return JsonProblem(e.message, off, line, col);
  }
}

/// Pretty-prints JSON, or returns null if [text] is not valid JSON (including
/// JSON that uses unquoted `{{variables}}`). Key order is preserved; number
/// formatting follows Dart (for example `1e2` becomes `100.0`).
String? formatJson(String text, {int indent = 2}) {
  try {
    final v = jsonDecode(text);
    return JsonEncoder.withIndent(' ' * indent).convert(v);
  } on FormatException {
    return null;
  }
}

String? minifyJson(String text) {
  try {
    return jsonEncode(jsonDecode(text));
  } on FormatException {
    return null;
  }
}
