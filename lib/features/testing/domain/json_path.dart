import 'dart:convert';

/// Minimal JSONPath: `$`, `.key`, `['key']`, `[index]`. No wildcards or
/// filters; unsupported syntax makes [parse] return null.
class JsonPath {
  JsonPath._(this._steps);

  final List<Object> _steps; // String key or int index

  static JsonPath? parse(String expr) {
    final s = expr.trim();
    if (s.isEmpty || s[0] != r'$') return null;
    final steps = <Object>[];
    var i = 1;
    while (i < s.length) {
      final ch = s[i];
      if (ch == '.') {
        var j = i + 1;
        while (j < s.length && s[j] != '.' && s[j] != '[') {
          j++;
        }
        final key = s.substring(i + 1, j);
        if (key.isEmpty) return null;
        steps.add(key);
        i = j;
      } else if (ch == '[') {
        final close = s.indexOf(']', i);
        if (close < 0) return null;
        final inner = s.substring(i + 1, close).trim();
        if (inner.length >= 2 &&
            ((inner.startsWith("'") && inner.endsWith("'")) ||
                (inner.startsWith('"') && inner.endsWith('"')))) {
          steps.add(inner.substring(1, inner.length - 1));
        } else {
          final n = int.tryParse(inner);
          if (n == null) return null;
          steps.add(n);
        }
        i = close + 1;
      } else {
        return null;
      }
    }
    return JsonPath._(steps);
  }

  /// Returns (found, value).
  (bool, Object?) evaluate(Object? root) {
    Object? cur = root;
    for (final step in _steps) {
      if (step is String) {
        if (cur is Map && cur.containsKey(step)) {
          cur = cur[step];
        } else {
          return (false, null);
        }
      } else if (step is int) {
        if (cur is List && step >= 0 && step < cur.length) {
          cur = cur[step];
        } else {
          return (false, null);
        }
      }
    }
    return (true, cur);
  }
}

/// Renders a JSON value as text for comparisons and variable extraction.
String jsonValueToString(Object? v) {
  if (v == null) return 'null';
  if (v is String) return v;
  return jsonEncode(v);
}
