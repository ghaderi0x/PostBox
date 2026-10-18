/// Central place that decides what counts as sensitive and how it is masked.
class Redactor {
  const Redactor._();

  static const String mask = '••••';

  static const Set<String> _sensitiveHeaders = <String>{
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-csrf-token',
  };

  static bool isSensitiveHeader(String name) {
    final n = name.toLowerCase();
    return _sensitiveHeaders.contains(n) ||
        n.contains('token') ||
        n.contains('secret') ||
        n.contains('password') ||
        n.contains('api-key') ||
        n.contains('apikey');
  }

  static String headerValue(String name, String value) =>
      isSensitiveHeader(name) ? mask : value;

  /// Removes userinfo and masks every query value. Tolerates `{{vars}}`.
  static String url(String raw) {
    var s = raw.replaceFirstMapped(
      RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*://)[^/@?#]*@'),
      (m) => m[1]!,
    );
    final hash = s.indexOf('#');
    if (hash >= 0) s = s.substring(0, hash);
    final q = s.indexOf('?');
    if (q < 0) return s;
    final base = s.substring(0, q);
    final pairs = s.substring(q + 1).split('&').where((p) => p.isNotEmpty);
    final masked = pairs.map((p) {
      final eq = p.indexOf('=');
      return eq < 0 ? p : '${p.substring(0, eq)}=$mask';
    });
    final joined = masked.join('&');
    return joined.isEmpty ? base : '$base?$joined';
  }

  /// Best-effort scrub of free text such as log lines.
  static String freeText(String input) {
    var s = input;
    s = s.replaceAllMapped(
      RegExp(r'(https?://[^\s?#]+)\?[^\s]*'),
      (m) => '${m[1]}?$mask',
    );
    s = s.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      (_) => 'Bearer $mask',
    );
    s = s.replaceAllMapped(
      RegExp(
        r'(authorization|token|password|passwd|secret|api[-_]?key)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      (m) => '${m[1]}: $mask',
    );
    return s;
  }
}
