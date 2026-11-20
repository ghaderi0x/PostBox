import 'dart:typed_data';

import 'cookie_jar.dart';

/// Redirect behaviour. Explicit so it can be tested and shown in the UI.
enum RedirectPolicy { never, sameOrigin, always }

class HttpRequestSpec {
  const HttpRequestSpec({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
    this.timeout = const Duration(seconds: 30),
    this.redirectPolicy = RedirectPolicy.always,
    this.maxRedirects = 10,
    this.maxResponseBytes = 10 * 1024 * 1024,
    this.proxy,
    this.allowInvalidCertificates = false,
    this.cookieJar,
    this.preferHttp2 = false,
    this.clientCertPath,
    this.clientKeyPath,
    this.clientKeyPassword,
    this.caCertPath,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Uint8List? body;
  final Duration timeout;
  final RedirectPolicy redirectPolicy;
  final int maxRedirects;

  /// Bytes beyond this limit are dropped and [HttpResult.truncated] is set.
  final int maxResponseBytes;

  /// `host:port`, or null for direct connections.
  final String? proxy;

  /// Must be an explicit opt-in. Defaults to false (TLS validated).
  final bool allowInvalidCertificates;

  /// When set, stored cookies are sent (unless the request has its own Cookie
  /// header) and Set-Cookie responses are stored, hop by hop.
  final CookieJar? cookieJar;

  /// Offer HTTP/2 through ALPN on https URLs without a proxy. Falls back to
  /// HTTP/1.1 when the server does not select h2.
  final bool preferHttp2;

  /// Mutual TLS: PEM certificate chain, PEM private key (defaults to the
  /// certificate file when it holds both) and the key's password.
  final String? clientCertPath;
  final String? clientKeyPath;
  final String? clientKeyPassword;

  /// Extra PEM trust anchors, added to the system roots.
  final String? caCertPath;

  bool get usesCustomTls =>
      (clientCertPath ?? '').isNotEmpty || (caCertPath ?? '').isNotEmpty;
}

/// Where the time went. dart:io does not expose DNS, TCP and TLS separately,
/// so [connect] covers all of them together.
class HttpTimings {
  const HttpTimings({
    this.connect = Duration.zero,
    this.wait = Duration.zero,
    this.download = Duration.zero,
    this.redirects = Duration.zero,
  });

  /// DNS lookup, TCP connect and TLS handshake of the final request.
  final Duration connect;

  /// Sending the request until the response headers arrived (time to first byte).
  final Duration wait;

  /// Reading the response body.
  final Duration download;

  /// Time spent on earlier requests of a redirect chain.
  final Duration redirects;
}

/// Facts about the server certificate of an https response.
class TlsInfo {
  const TlsInfo({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.sha1,
    this.pem = '',
  });

  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;

  /// Lowercase hex SHA-1 of the DER certificate.
  final String sha1;
  final String pem;

  bool isExpiredAt(DateTime now) =>
      now.isAfter(validTo) || now.isBefore(validFrom);
}

/// Standard reason phrases, used where the protocol carries none (HTTP/2).
String reasonPhraseFor(int status) =>
    const <int, String>{
      100: 'Continue',
      101: 'Switching Protocols',
      200: 'OK',
      201: 'Created',
      202: 'Accepted',
      204: 'No Content',
      206: 'Partial Content',
      301: 'Moved Permanently',
      302: 'Found',
      303: 'See Other',
      304: 'Not Modified',
      307: 'Temporary Redirect',
      308: 'Permanent Redirect',
      400: 'Bad Request',
      401: 'Unauthorized',
      403: 'Forbidden',
      404: 'Not Found',
      405: 'Method Not Allowed',
      408: 'Request Timeout',
      409: 'Conflict',
      410: 'Gone',
      415: 'Unsupported Media Type',
      418: "I'm a teapot",
      422: 'Unprocessable Entity',
      429: 'Too Many Requests',
      500: 'Internal Server Error',
      501: 'Not Implemented',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
      504: 'Gateway Timeout',
    }[status] ??
    '';

class HttpResult {
  const HttpResult({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    required this.truncated,
    required this.duration,
    required this.finalUrl,
    required this.redirects,
    this.timings = const HttpTimings(),
    this.tls,
    this.protocol = 'HTTP/1.1',
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;
  final Uint8List body;
  final bool truncated;
  final Duration duration;
  final Uri finalUrl;
  final List<Uri> redirects;
  final HttpTimings timings;

  /// Server certificate for https responses, null otherwise.
  final TlsInfo? tls;

  /// `HTTP/1.1` or `h2`.
  final String protocol;

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value.join(', ');
    }
    return null;
  }

  String? get contentType => header('content-type');
}

enum HttpFailureKind {
  timeout,
  cancelled,
  tls,
  connection,
  protocol,
  tooManyRedirects,
}

class HttpFailure implements Exception {
  const HttpFailure(this.kind, this.message);
  final HttpFailureKind kind;
  final String message;

  @override
  String toString() => 'HttpFailure(${kind.name}): $message';
}

class CancelToken {
  bool _cancelled = false;
  void Function()? _listener;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _listener?.call();
  }

  /// Called by engine implementations.
  void onCancel(void Function() listener) {
    _listener = listener;
    if (_cancelled) listener();
  }
}

abstract interface class HttpEngine {
  Future<HttpResult> send(HttpRequestSpec spec, {CancelToken? cancel});
}
