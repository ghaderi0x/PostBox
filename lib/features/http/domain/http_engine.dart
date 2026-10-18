import 'dart:typed_data';

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
}

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
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;
  final Uint8List body;
  final bool truncated;
  final Duration duration;
  final Uri finalUrl;
  final List<Uri> redirects;

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
