import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../domain/http_engine.dart';
import 'http2_exchange.dart';
import 'raw_exchange.dart';

/// Builds the TLS context for custom CA and client certificates (mTLS), or
/// null when the platform defaults are enough.
///
/// Throws [HttpFailure] (kind tls) when a file cannot be read or parsed, so
/// the user sees a clear message instead of a generic connection error.
SecurityContext? buildSecurityContext(HttpRequestSpec spec) {
  if (!spec.usesCustomTls) return null;
  try {
    final ctx = SecurityContext(withTrustedRoots: true);
    final ca = spec.caCertPath ?? '';
    if (ca.isNotEmpty) ctx.setTrustedCertificates(ca);
    final cert = spec.clientCertPath ?? '';
    if (cert.isNotEmpty) {
      ctx.useCertificateChain(cert);
      final key = (spec.clientKeyPath ?? '').isNotEmpty
          ? spec.clientKeyPath!
          : cert;
      final pw = spec.clientKeyPassword ?? '';
      ctx.usePrivateKey(key, password: pw.isEmpty ? null : pw);
    }
    return ctx;
  } on TlsException catch (e) {
    throw HttpFailure(
      HttpFailureKind.tls,
      'Client certificate or CA file could not be used: ${e.message}',
    );
  } on FileSystemException catch (e) {
    throw HttpFailure(
      HttpFailureKind.tls,
      'Certificate file not readable: ${e.path ?? e.message}',
    );
  }
}

/// Applies timeout, TLS and proxy settings from [spec] to a new client.
/// Shared by the request engine, SSE and WebSocket sessions.
HttpClient createConfiguredClient(HttpRequestSpec spec) {
  final client = HttpClient(context: buildSecurityContext(spec))
    ..connectionTimeout = spec.timeout;
  if (spec.allowInvalidCertificates) {
    client.badCertificateCallback = (cert, host, port) => true;
  }
  final proxy = spec.proxy;
  if (proxy != null && proxy.isNotEmpty) {
    client.findProxy = (uri) => 'PROXY $proxy';
  }
  return client;
}

/// Everything that must be torn down when a request is cancelled or ends.
class _Session {
  _Session(this.client);

  final HttpClient client;
  final List<void Function()> _aborters = <void Function()>[];
  final Set<String> http2Refused = <String>{};

  void onAbort(void Function() f) => _aborters.add(f);

  void abort() {
    client.close(force: true);
    for (final f in List<void Function()>.of(_aborters)) {
      f();
    }
  }
}

/// [HttpEngine] built on dart:io [HttpClient], with an optional HTTP/2 path.
///
/// Redirects are followed manually so the policy is explicit and sensitive
/// headers are never forwarded to a different origin. Cookies from the jar
/// are computed per hop for the same reason.
class IoHttpEngine implements HttpEngine {
  const IoHttpEngine();

  static const Set<String> _sensitiveHeaders = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
  };

  @override
  Future<HttpResult> send(HttpRequestSpec spec, {CancelToken? cancel}) async {
    // Throws HttpFailure(tls) when a certificate file cannot be loaded.
    final session = _Session(createConfiguredClient(spec));
    cancel?.onCancel(session.abort);

    final watch = Stopwatch()..start();
    try {
      return await _run(session, spec, watch, cancel).timeout(spec.timeout);
    } on TimeoutException {
      session.abort();
      throw HttpFailure(
        HttpFailureKind.timeout,
        'No complete response within ${spec.timeout.inSeconds}s.',
      );
    } on HttpFailure {
      rethrow;
    } on HandshakeException catch (e) {
      throw HttpFailure(
        HttpFailureKind.tls,
        'TLS handshake failed: ${e.message}',
      );
    } on TlsException catch (e) {
      throw HttpFailure(HttpFailureKind.tls, 'TLS error: ${e.message}');
    } on SocketException catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw const HttpFailure(
          HttpFailureKind.cancelled,
          'Request cancelled.',
        );
      }
      throw HttpFailure(
        HttpFailureKind.connection,
        'Connection failed: ${e.message}',
      );
    } on HttpException catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw const HttpFailure(
          HttpFailureKind.cancelled,
          'Request cancelled.',
        );
      }
      throw HttpFailure(HttpFailureKind.protocol, 'HTTP error: ${e.message}');
    } on Http2Failure catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw const HttpFailure(
          HttpFailureKind.cancelled,
          'Request cancelled.',
        );
      }
      throw HttpFailure(HttpFailureKind.protocol, 'HTTP/2 error: ${e.message}');
    } finally {
      session.abort();
    }
  }

  bool _canTryHttp2(HttpRequestSpec spec, Uri url, _Session s) =>
      spec.preferHttp2 &&
      url.scheme == 'https' &&
      (spec.proxy == null || spec.proxy!.isEmpty) &&
      !s.http2Refused.contains('${url.host}:${url.port}');

  Future<HttpResult> _run(
    _Session session,
    HttpRequestSpec spec,
    Stopwatch watch,
    CancelToken? cancel,
  ) async {
    var method = spec.method;
    var url = spec.url;
    var body = spec.body;
    var headers = Map<String, String>.of(spec.headers);
    final chain = <Uri>[];
    var earlier = Duration.zero;
    final ctx = buildSecurityContext(spec);

    for (var hop = 0; ; hop++) {
      final hopWatch = Stopwatch()..start();
      final hopHeaders = _withCookies(headers, spec, url);

      RawExchange? raw;
      if (_canTryHttp2(spec, url, session)) {
        try {
          raw = await http2Exchange(
            method: method,
            url: url,
            headers: hopHeaders,
            body: body,
            spec: spec,
            context: ctx,
            onAbort: session.onAbort,
          );
        } on Http2NotNegotiated {
          session.http2Refused.add('${url.host}:${url.port}');
        }
      }
      raw ??= await _http1Exchange(
        session.client,
        method,
        url,
        hopHeaders,
        body,
      );

      _storeCookies(spec, url, raw.headers);

      final location = raw.header(HttpHeaders.locationHeader);
      final isRedirect =
          const <int>{301, 302, 303, 307, 308}.contains(raw.status) &&
          location != null;

      if (isRedirect && spec.redirectPolicy != RedirectPolicy.never) {
        final next = url.resolve(location);
        final crossOrigin = !_sameOrigin(url, next);
        if (crossOrigin && spec.redirectPolicy == RedirectPolicy.sameOrigin) {
          return _finish(raw, spec, watch, url, chain, earlier);
        }
        if (hop >= spec.maxRedirects) {
          await raw.close();
          throw HttpFailure(
            HttpFailureKind.tooManyRedirects,
            'More than ${spec.maxRedirects} redirects.',
          );
        }
        if (crossOrigin) {
          headers = <String, String>{
            for (final e in headers.entries)
              if (!_sensitiveHeaders.contains(e.key.toLowerCase()))
                e.key: e.value,
          };
        }
        final code = raw.status;
        final toGet =
            code == 303 || ((code == 301 || code == 302) && method == 'POST');
        if (toGet) {
          method = 'GET';
          body = null;
          headers = <String, String>{
            for (final e in headers.entries)
              if (!e.key.toLowerCase().startsWith('content-')) e.key: e.value,
          };
        }
        await raw.close();
        earlier += hopWatch.elapsed;
        chain.add(next);
        url = next;
        continue;
      }
      return _finish(raw, spec, watch, url, chain, earlier);
    }
  }

  /// Adds the jar's Cookie header unless the request set one itself. Computed
  /// for each hop, so a cookie never follows a redirect to another host.
  Map<String, String> _withCookies(
    Map<String, String> headers,
    HttpRequestSpec spec,
    Uri url,
  ) {
    final jar = spec.cookieJar;
    if (jar == null) return headers;
    if (headers.keys.any((k) => k.toLowerCase() == 'cookie')) return headers;
    final value = jar.cookieHeader(url);
    if (value == null) return headers;
    return <String, String>{...headers, 'Cookie': value};
  }

  void _storeCookies(
    HttpRequestSpec spec,
    Uri url,
    Map<String, List<String>> headers,
  ) {
    final jar = spec.cookieJar;
    if (jar == null) return;
    final values = <String>[
      for (final e in headers.entries)
        if (e.key.toLowerCase() == 'set-cookie') ...e.value,
    ];
    if (values.isNotEmpty) jar.storeFromResponse(url, values);
  }

  Future<RawExchange> _http1Exchange(
    HttpClient client,
    String method,
    Uri url,
    Map<String, String> headers,
    Uint8List? body,
  ) async {
    final sw = Stopwatch()..start();
    final request = await client.openUrl(method, url);
    final connect = sw.elapsed;
    request.followRedirects = false;
    headers.forEach(
      (k, v) => request.headers.set(k, v, preserveHeaderCase: true),
    );
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    final wait = sw.elapsed - connect;

    final headerMap = <String, List<String>>{};
    response.headers.forEach(
      (name, values) => headerMap[name] = List<String>.of(values),
    );

    TlsInfo? tls;
    final cert = response.certificate;
    if (cert != null) {
      tls = TlsInfo(
        subject: cert.subject,
        issuer: cert.issuer,
        validFrom: cert.startValidity,
        validTo: cert.endValidity,
        sha1: cert.sha1.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        pem: cert.pem,
      );
    }
    return RawExchange(
      status: response.statusCode,
      reason: response.reasonPhrase,
      headers: headerMap,
      body: response,
      protocol: 'HTTP/1.1',
      connect: connect,
      wait: wait,
      tls: tls,
      close: () async {
        // Dropping the unread body is enough; the client is closed at the end.
      },
    );
  }

  Future<HttpResult> _finish(
    RawExchange raw,
    HttpRequestSpec spec,
    Stopwatch watch,
    Uri url,
    List<Uri> chain,
    Duration earlier,
  ) async {
    final bodyWatch = Stopwatch()..start();
    final builder = BytesBuilder(copy: false);
    var truncated = false;
    try {
      await for (final chunk in raw.body) {
        final remaining = spec.maxResponseBytes - builder.length;
        if (chunk.length > remaining) {
          builder.add(chunk.sublist(0, remaining));
          truncated = true;
          break;
        }
        builder.add(chunk);
      }
    } finally {
      await raw.close();
    }
    watch.stop();
    return HttpResult(
      statusCode: raw.status,
      reasonPhrase: raw.reason,
      headers: raw.headers,
      body: builder.takeBytes(),
      truncated: truncated,
      duration: watch.elapsed,
      finalUrl: url,
      redirects: List<Uri>.unmodifiable(chain),
      timings: HttpTimings(
        connect: raw.connect,
        wait: raw.wait,
        download: bodyWatch.elapsed,
        redirects: earlier,
      ),
      tls: raw.tls,
      protocol: raw.protocol,
    );
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}
