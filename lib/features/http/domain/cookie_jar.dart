import 'dart:io' show HttpDate;

/// One stored cookie.
class StoredCookie {
  const StoredCookie({
    required this.domain,
    required this.path,
    required this.name,
    required this.value,
    this.hostOnly = true,
    this.secure = false,
    this.httpOnly = false,
    this.sameSite = '',
    this.expires,
    required this.created,
  });

  /// Lowercase host (host-only cookies) or domain attribute without a leading dot.
  final String domain;
  final String path;
  final String name;
  final String value;
  final bool hostOnly;
  final bool secure;
  final bool httpOnly;
  final String sameSite;

  /// Null for session cookies. Session cookies are kept until the jar is
  /// cleared (there is no "browser session" in an API client).
  final DateTime? expires;
  final DateTime created;

  bool isExpired(DateTime now) => expires != null && !expires!.isAfter(now);

  /// Identity inside the jar (RFC 6265 section 5.3).
  String get key => '$domain\u0000$path\u0000$name';
}

/// Cookie storage used by the HTTP engine. See [CookieJarImpl].
abstract interface class CookieJar {
  /// Value of the `Cookie` request header for [url], or null when none apply.
  String? cookieHeader(Uri url);

  /// Stores the `Set-Cookie` values of a response received from [url].
  void storeFromResponse(Uri url, List<String> setCookieValues);

  List<StoredCookie> all();
  void delete(StoredCookie c);
  void clear();
}

/// Optional backing store; the jar keeps everything in memory and writes
/// changes through.
abstract interface class CookiePersistence {
  List<StoredCookie> load();
  void upsert(StoredCookie c);
  void remove(StoredCookie c);
  void clear();
}

/// RFC 6265 style cookie jar with size limits.
///
/// Known simplifications (documented in docs/ARCHITECTURE.md): there is no
/// public-suffix list, so a server may set a cookie for a registrable suffix
/// such as `co.uk`; SameSite is stored but not enforced because an API client
/// has no cross-site context.
class CookieJarImpl implements CookieJar {
  CookieJarImpl({CookiePersistence? persistence, DateTime Function()? clock})
    : _persistence = persistence,
      _clock = clock ?? DateTime.now {
    final loaded = persistence?.load() ?? const <StoredCookie>[];
    final now = _clock();
    for (final c in loaded) {
      if (c.isExpired(now)) {
        persistence?.remove(c);
      } else {
        _cookies[c.key] = c;
      }
    }
  }

  static const int maxCookies = 3000;
  static const int maxPerDomain = 100;
  static const int maxPairLength = 4096;

  final CookiePersistence? _persistence;
  final DateTime Function() _clock;
  final Map<String, StoredCookie> _cookies = <String, StoredCookie>{};

  @override
  List<StoredCookie> all() {
    _purgeExpired();
    final list = _cookies.values.toList()
      ..sort((a, b) {
        final d = a.domain.compareTo(b.domain);
        return d != 0 ? d : a.name.compareTo(b.name);
      });
    return list;
  }

  @override
  void delete(StoredCookie c) {
    if (_cookies.remove(c.key) != null) _persistence?.remove(c);
  }

  @override
  void clear() {
    _cookies.clear();
    _persistence?.clear();
  }

  void _purgeExpired() {
    final now = _clock();
    final dead = _cookies.values.where((c) => c.isExpired(now)).toList();
    for (final c in dead) {
      _cookies.remove(c.key);
      _persistence?.remove(c);
    }
  }

  static bool _isLocal(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '[::1]' ||
      host == '::1';

  static bool domainMatches(
    String host,
    String domain, {
    required bool hostOnly,
  }) {
    if (host == domain) return true;
    if (hostOnly) return false;
    // IP addresses never match by suffix.
    if (RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains(':')) return false;
    return host.endsWith('.$domain');
  }

  static bool pathMatches(String requestPath, String cookiePath) {
    final rp = requestPath.isEmpty ? '/' : requestPath;
    if (rp == cookiePath) return true;
    if (rp.startsWith(cookiePath)) {
      if (cookiePath.endsWith('/')) return true;
      if (rp.length > cookiePath.length && rp[cookiePath.length] == '/') {
        return true;
      }
    }
    return false;
  }

  static String _defaultPath(Uri url) {
    final p = url.path;
    if (p.isEmpty || !p.startsWith('/')) return '/';
    final i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }

  @override
  String? cookieHeader(Uri url) {
    _purgeExpired();
    final host = url.host.toLowerCase();
    final isHttps = url.scheme == 'https';
    final path = url.path.isEmpty ? '/' : url.path;
    final matching =
        _cookies.values.where((c) {
          if (c.secure && !isHttps && !_isLocal(host)) return false;
          if (!domainMatches(host, c.domain, hostOnly: c.hostOnly)) {
            return false;
          }
          return pathMatches(path, c.path);
        }).toList()..sort((a, b) {
          final byPath = b.path.length.compareTo(a.path.length);
          return byPath != 0 ? byPath : a.created.compareTo(b.created);
        });
    if (matching.isEmpty) return null;
    return matching.map((c) => '${c.name}=${c.value}').join('; ');
  }

  @override
  void storeFromResponse(Uri url, List<String> setCookieValues) {
    final now = _clock();
    for (final raw in setCookieValues) {
      final parsed = parseSetCookie(raw, url, now);
      if (parsed == null) continue;
      if (parsed.deleteRequested) {
        final victim = _cookies.remove(parsed.cookie.key);
        if (victim != null) _persistence?.remove(victim);
        continue;
      }
      final existing = _cookies[parsed.cookie.key];
      // Keep the creation time of a replaced cookie (RFC 6265 5.3 step 11).
      final c = existing == null
          ? parsed.cookie
          : StoredCookie(
              domain: parsed.cookie.domain,
              path: parsed.cookie.path,
              name: parsed.cookie.name,
              value: parsed.cookie.value,
              hostOnly: parsed.cookie.hostOnly,
              secure: parsed.cookie.secure,
              httpOnly: parsed.cookie.httpOnly,
              sameSite: parsed.cookie.sameSite,
              expires: parsed.cookie.expires,
              created: existing.created,
            );
      _cookies[c.key] = c;
      _persistence?.upsert(c);
      _enforceLimits(c.domain);
    }
  }

  void _enforceLimits(String domain) {
    void evict(Iterable<StoredCookie> pool, int limit) {
      final list = pool.toList()
        ..sort((a, b) => a.created.compareTo(b.created));
      for (var i = 0; i < list.length - limit; i++) {
        _cookies.remove(list[i].key);
        _persistence?.remove(list[i]);
      }
    }

    evict(_cookies.values.where((c) => c.domain == domain), maxPerDomain);
    if (_cookies.length > maxCookies) evict(_cookies.values, maxCookies);
  }
}

class ParsedSetCookie {
  const ParsedSetCookie(this.cookie, {this.deleteRequested = false});
  final StoredCookie cookie;

  /// True when the server expired the cookie (Max-Age <= 0 or past Expires).
  final bool deleteRequested;
}

/// Parses one `Set-Cookie` header received from [url]. Returns null when the
/// cookie must be rejected (malformed, wrong domain, insecure Secure cookie,
/// violated `__Host-` / `__Secure-` prefix rules, too large).
ParsedSetCookie? parseSetCookie(String header, Uri url, DateTime now) {
  final parts = header.split(';');
  if (parts.isEmpty) return null;
  final pair = parts.first.trim();
  final eq = pair.indexOf('=');
  if (eq <= 0) return null;
  final name = pair.substring(0, eq).trim();
  final value = pair.substring(eq + 1).trim();
  if (name.isEmpty || pair.length > CookieJarImpl.maxPairLength) return null;

  final host = url.host.toLowerCase();
  String? domainAttr;
  String? pathAttr;
  DateTime? expires;
  int? maxAge;
  var secure = false;
  var httpOnly = false;
  var sameSite = '';

  for (final raw in parts.skip(1)) {
    final a = raw.trim();
    if (a.isEmpty) continue;
    final i = a.indexOf('=');
    final key = (i < 0 ? a : a.substring(0, i)).trim().toLowerCase();
    final val = i < 0 ? '' : a.substring(i + 1).trim();
    switch (key) {
      case 'domain':
        var d = val.toLowerCase();
        if (d.startsWith('.')) d = d.substring(1);
        if (d.isNotEmpty) domainAttr = d;
      case 'path':
        if (val.startsWith('/')) pathAttr = val;
      case 'expires':
        try {
          expires = HttpDate.parse(val);
        } on Object {
          // Unparseable dates are ignored, as browsers do for invalid ones.
        }
      case 'max-age':
        maxAge = int.tryParse(val);
      case 'secure':
        secure = true;
      case 'httponly':
        httpOnly = true;
      case 'samesite':
        sameSite = val;
    }
  }

  final local = CookieJarImpl._isLocal(host);
  if (secure && url.scheme != 'https' && !local) return null;
  if (name.startsWith('__Secure-') && !secure) return null;
  if (name.startsWith('__Host-') &&
      (!secure || domainAttr != null || (pathAttr ?? '/') != '/')) {
    return null;
  }

  String domain;
  var hostOnly = true;
  if (domainAttr != null) {
    // A cookie may only be set for the request host or a parent domain, and a
    // bare top-level name such as "com" is refused (no public-suffix list).
    final isIpHost = RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains(':');
    // An IP address can only set cookies for exactly itself.
    final matches =
        host == domainAttr || (!isIpHost && host.endsWith('.$domainAttr'));
    if (!matches) return null;
    if (!domainAttr.contains('.') && domainAttr != host && !local) return null;
    domain = domainAttr;
    hostOnly = false;
  } else {
    domain = host;
  }

  DateTime? expiry;
  var del = false;
  if (maxAge != null) {
    if (maxAge <= 0) {
      del = true;
    } else {
      expiry = now.add(Duration(seconds: maxAge));
    }
  } else if (expires != null) {
    expiry = expires.toUtc();
    if (!expiry.isAfter(now)) del = true;
  }

  final c = StoredCookie(
    domain: domain,
    path: pathAttr ?? CookieJarImpl._defaultPath(url),
    name: name,
    value: value,
    hostOnly: hostOnly,
    secure: secure,
    httpOnly: httpOnly,
    sameSite: sameSite,
    expires: expiry,
    created: now,
  );
  return ParsedSetCookie(c, deleteRequested: del);
}
