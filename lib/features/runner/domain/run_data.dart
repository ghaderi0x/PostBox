import 'dart:convert';

/// Data file for a data-driven run: every row becomes one iteration whose
/// columns are available to the requests as `{{column}}` variables.
class RunData {
  const RunData(this.rows, {this.columns = const <String>[]});

  final List<Map<String, String>> rows;
  final List<String> columns;

  bool get isEmpty => rows.isEmpty;
}

class RunDataException implements Exception {
  const RunDataException(this.code, [this.detail = '']);

  /// `too_large`, `too_many_rows`, `too_many_columns`, `empty`, `bad_json`,
  /// `bad_csv`.
  final String code;
  final String detail;

  @override
  String toString() =>
      'RunDataException($code${detail.isEmpty ? '' : ': $detail'})';
}

const int kMaxRunDataBytes = 1024 * 1024;
const int kMaxRunDataRows = 1000;
const int kMaxRunDataColumns = 100;

/// Parses CSV (comma, semicolon or tab separated, first row is the header)
/// or a JSON array of flat objects.
RunData parseRunData(String text) {
  if (text.length > kMaxRunDataBytes) throw const RunDataException('too_large');
  final trimmed = text.trim();
  if (trimmed.isEmpty) throw const RunDataException('empty');
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    return _fromJson(trimmed);
  }
  return _fromCsv(text);
}

String _cell(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return jsonEncode(v);
}

RunData _fromJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw RunDataException('bad_json', e.message);
  }
  final list = decoded is List ? decoded : <Object?>[decoded];
  if (list.length > kMaxRunDataRows) {
    throw const RunDataException('too_many_rows');
  }
  final columns = <String>[];
  final rows = <Map<String, String>>[];
  for (final item in list) {
    if (item is! Map) {
      throw const RunDataException('bad_json', 'rows must be objects');
    }
    final row = <String, String>{};
    item.forEach((k, v) {
      final key = '$k'.trim();
      if (key.isEmpty) return;
      row[key] = _cell(v);
      if (!columns.contains(key)) columns.add(key);
    });
    rows.add(row);
  }
  if (columns.length > kMaxRunDataColumns) {
    throw const RunDataException('too_many_columns');
  }
  if (rows.isEmpty) throw const RunDataException('empty');
  return RunData(rows, columns: columns);
}

List<List<String>> _csvRecords(String text, String delimiter) {
  final records = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // Skip completely empty lines.
    if (!(row.length == 1 && row.first.isEmpty)) records.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (ch == delimiter) {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      // Handled by the following \n; a lone \r also ends the row.
      if (i + 1 >= text.length || text[i + 1] != '\n') endRow();
    } else {
      field.write(ch);
    }
    i++;
    if (records.length > kMaxRunDataRows + 1) {
      throw const RunDataException('too_many_rows');
    }
  }
  if (inQuotes) throw const RunDataException('bad_csv', 'unterminated quote');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return records;
}

RunData _fromCsv(String text) {
  // Pick the delimiter that appears most in the header line.
  final firstLine = text
      .split(RegExp(r'\r?\n'))
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  var delimiter = ',';
  var best = -1;
  for (final d in <String>[',', ';', '\t']) {
    final n = d.allMatches(firstLine).length;
    if (n > best) {
      best = n;
      delimiter = d;
    }
  }
  final records = _csvRecords(text, delimiter);
  if (records.length < 2) throw const RunDataException('empty');
  final header = records.first.map((h) => h.trim()).toList();
  if (header.length > kMaxRunDataColumns) {
    throw const RunDataException('too_many_columns');
  }
  final columns = <String>[
    for (final h in header)
      if (h.isNotEmpty) h,
  ];
  if (columns.isEmpty) {
    throw const RunDataException('bad_csv', 'missing header');
  }
  final rows = <Map<String, String>>[];
  for (final r in records.skip(1)) {
    final row = <String, String>{};
    for (var c = 0; c < header.length; c++) {
      if (header[c].isEmpty) continue;
      row[header[c]] = c < r.length ? r[c] : '';
    }
    rows.add(row);
  }
  return RunData(rows, columns: columns);
}
