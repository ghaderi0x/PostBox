import 'dart:convert';

import '../../../core/util/ids.dart';
import '../../../core/util/json_util.dart';
import '../../http/domain/http_engine.dart';
import 'json_path.dart';

enum AssertionKind {
  statusEquals,
  statusIsSuccess,
  headerEquals,
  headerContains,
  bodyContains,
  jsonPathEquals,
  jsonPathExists,
  durationLessThanMs,
}

class Assertion {
  const Assertion({
    required this.id,
    required this.kind,
    this.target = '',
    this.expected = '',
  });

  final String id;
  final AssertionKind kind;

  /// Header name or JSONPath, depending on [kind].
  final String target;
  final String expected;

  factory Assertion.blank(AssertionKind kind) =>
      Assertion(id: newId(), kind: kind);

  Assertion copyWith({AssertionKind? kind, String? target, String? expected}) =>
      Assertion(
        id: id,
        kind: kind ?? this.kind,
        target: target ?? this.target,
        expected: expected ?? this.expected,
      );

  bool get usesTarget =>
      kind == AssertionKind.headerEquals ||
      kind == AssertionKind.headerContains ||
      kind == AssertionKind.jsonPathEquals ||
      kind == AssertionKind.jsonPathExists;

  bool get usesExpected =>
      kind != AssertionKind.statusIsSuccess &&
      kind != AssertionKind.jsonPathExists;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'target': target,
    'expected': expected,
  };

  factory Assertion.fromJson(Object? j) {
    final m = asMap(j);
    return Assertion(
      id: asString(m['id']).isEmpty ? newId() : asString(m['id']),
      kind: enumByName(
        AssertionKind.values,
        m['kind'],
        AssertionKind.statusEquals,
      ),
      target: asString(m['target']),
      expected: asString(m['expected']),
    );
  }
}

class AssertionResult {
  const AssertionResult(this.assertion, this.passed, this.message);
  final Assertion assertion;
  final bool passed;

  /// Short explanation, never contains full bodies.
  final String message;
}

enum ExtractionSource { jsonPath, header }

/// Copies a value out of a response into a variable (request chaining).
class Extraction {
  const Extraction({
    required this.id,
    required this.variable,
    required this.source,
    required this.expression,
  });

  final String id;
  final String variable;
  final ExtractionSource source;
  final String expression;

  factory Extraction.blank() => Extraction(
    id: newId(),
    variable: '',
    source: ExtractionSource.jsonPath,
    expression: '',
  );

  Extraction copyWith({
    String? variable,
    ExtractionSource? source,
    String? expression,
  }) => Extraction(
    id: id,
    variable: variable ?? this.variable,
    source: source ?? this.source,
    expression: expression ?? this.expression,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'variable': variable,
    'source': source.name,
    'expression': expression,
  };

  factory Extraction.fromJson(Object? j) {
    final m = asMap(j);
    return Extraction(
      id: asString(m['id']).isEmpty ? newId() : asString(m['id']),
      variable: asString(m['variable']),
      source: enumByName(
        ExtractionSource.values,
        m['source'],
        ExtractionSource.jsonPath,
      ),
      expression: asString(m['expression']),
    );
  }
}

Object? _tryDecodeJson(HttpResult r) {
  try {
    return jsonDecode(utf8.decode(r.body, allowMalformed: true));
  } on FormatException {
    return null;
  }
}

List<AssertionResult> evaluateAssertions(
  List<Assertion> assertions,
  HttpResult r,
) {
  Object? json;
  var jsonTried = false;
  Object? jsonBody() {
    if (!jsonTried) {
      jsonTried = true;
      json = _tryDecodeJson(r);
    }
    return json;
  }

  final out = <AssertionResult>[];
  for (final a in assertions) {
    switch (a.kind) {
      case AssertionKind.statusEquals:
        final want = int.tryParse(a.expected.trim());
        out.add(
          AssertionResult(
            a,
            want != null && r.statusCode == want,
            'status ${r.statusCode}, expected ${a.expected}',
          ),
        );
      case AssertionKind.statusIsSuccess:
        out.add(
          AssertionResult(
            a,
            r.statusCode >= 200 && r.statusCode < 300,
            'status ${r.statusCode}',
          ),
        );
      case AssertionKind.headerEquals:
        final v = r.header(a.target);
        out.add(
          AssertionResult(
            a,
            v != null && v == a.expected,
            v == null
                ? 'header ${a.target} missing'
                : 'header ${a.target} differs',
          ),
        );
      case AssertionKind.headerContains:
        final v = r.header(a.target);
        out.add(
          AssertionResult(
            a,
            v != null && v.contains(a.expected),
            v == null
                ? 'header ${a.target} missing'
                : 'header ${a.target} lacks text',
          ),
        );
      case AssertionKind.bodyContains:
        final text = utf8.decode(r.body, allowMalformed: true);
        out.add(
          AssertionResult(
            a,
            text.contains(a.expected),
            'body does not contain the text',
          ),
        );
      case AssertionKind.jsonPathEquals:
        final path = JsonPath.parse(a.target);
        if (path == null) {
          out.add(AssertionResult(a, false, 'invalid JSONPath'));
          break;
        }
        final body = jsonBody();
        if (body == null) {
          out.add(AssertionResult(a, false, 'body is not JSON'));
          break;
        }
        final (found, value) = path.evaluate(body);
        out.add(
          AssertionResult(
            a,
            found && jsonValueToString(value) == a.expected,
            found ? 'value differs' : 'path not found',
          ),
        );
      case AssertionKind.jsonPathExists:
        final path = JsonPath.parse(a.target);
        final body = jsonBody();
        final ok = path != null && body != null && path.evaluate(body).$1;
        out.add(AssertionResult(a, ok, ok ? 'found' : 'path not found'));
      case AssertionKind.durationLessThanMs:
        final limit = int.tryParse(a.expected.trim());
        out.add(
          AssertionResult(
            a,
            limit != null && r.duration.inMilliseconds < limit,
            '${r.duration.inMilliseconds} ms, limit ${a.expected} ms',
          ),
        );
    }
  }
  return out;
}

/// Returns variable name to extracted value for every extraction that matched.
Map<String, String> applyExtractions(
  List<Extraction> extractions,
  HttpResult r,
) {
  final out = <String, String>{};
  Object? json;
  var tried = false;
  for (final e in extractions) {
    final name = e.variable.trim();
    if (name.isEmpty || e.expression.trim().isEmpty) continue;
    if (e.source == ExtractionSource.header) {
      final v = r.header(e.expression.trim());
      if (v != null) out[name] = v;
    } else {
      if (!tried) {
        tried = true;
        json = _tryDecodeJson(r);
      }
      final path = JsonPath.parse(e.expression);
      if (path == null || json == null) continue;
      final (found, value) = path.evaluate(json);
      if (found) out[name] = jsonValueToString(value);
    }
  }
  return out;
}
