import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../domain/http_engine.dart';

/// Applies timeout, TLS and proxy settings from [spec] to a new client.
/// Shared by the request engine, SSE and WebSocket sessions.
HttpClient createConfiguredClient(HttpRequestSpec spec) {
  final client = HttpClient()..connectionTimeout = spec.timeout;
  if (spec.allowInvalidCertificates) {
    client.badCertificateCallback = (cert, host, port) => true;
  }
  final proxy = spec.proxy;
  if (proxy != null && proxy.isNotEmpty) {
    client.findProxy = (uri) => 'PROXY $proxy';
  }
  return client;
}

/// [HttpEngine] built on dart:io [HttpClient].
///
/// Redirects are followed manually so the policy is explicit and sensitive
/// headers are never forwarded to a different origin.
class IoHttpEngine implements HttpEngine {
  const IoHttpEngine();

  static const Set<String> _sensitiveHeaders = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
  };

  @override
  Future<HttpResult> send(HttpRequestSpec spec, {CancelToken? cancel}) async {
    final client = createConfiguredClient(spec);
    cancel?.onCancel(() => client.close(force: true));

    final watch = Stopwatch()..start();
    try {
      return await _run(client, spec, watch).timeout(spec.timeout);
    } on TimeoutException {
      throw HttpFailure(
        HttpFailureKind.timeout,
        'No complete response within ${spec.timeout.inSeconds}s.',
      );
    } on HttpFailure {
      rethrow;
    } on HandshakeException catch (e) {
      throw HttpFailure(HttpFailureKind.tls, 'TLS handshake failed: ${e.message}');
    } on TlsException catch (e) {
      throw HttpFailure(HttpFailureKind.tls, 'TLS error: ${e.message}');
    } on SocketException catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw const HttpFailure(HttpFailureKind.cancelled, 'Request cancelled.');
      }
      throw HttpFailure(HttpFailureKind.connection, 'Connection failed: ${e.message}');
    } on HttpException catch (e) {
      if (cancel?.isCancelled ?? false) {
        throw const HttpFailure(HttpFailureKind.cancelled, 'Request cancelled.');
      }
      throw HttpFailure(HttpFailureKind.protocol, 'HTTP error: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpResult> _run(
    HttpClient client,
    HttpRequestSpec spec,
    Stopwatch watch,
  ) async {
    var method = spec.method;
    var url = spec.url;
    var body = spec.body;
    var headers = Map<String, String>.of(spec.headers);
    final chain = <Uri>[];

    for (var hop = 0; ; hop++) {
      final request = await client.openUrl(method, url);
      request.followRedirects = false;
      headers.forEach((k, v) => request.headers.set(k, v, preserveHeaderCase: true));
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();

      final location = response.headers.value(HttpHeaders.locationHeader);
      final isRedirect = const <int>{301, 302, 303, 307, 308}.contains(response.statusCode) &&
          location != null;

      if (isRedirect && spec.redirectPolicy != RedirectPolicy.never) {
        final next = url.resolve(location);
        final crossOrigin = !_sameOrigin(url, next);
        if (crossOrigin && spec.redirectPolicy == RedirectPolicy.sameOrigin) {
          return _finish(response, spec, watch, url, chain);
        }
        if (hop >= spec.maxRedirects) {
          throw HttpFailure(
            HttpFailureKind.tooManyRedirects,
            'More than ${spec.maxRedirects} redirects.',
          );
        }
        if (crossOrigin) {
          headers = {
            for (final e in headers.entries)
              if (!_sensitiveHeaders.contains(e.key.toLowerCase())) e.key: e.value,
          };
        }
        final code = response.statusCode;
        final toGet = code == 303 || ((code == 301 || code == 302) && method == 'POST');
        if (toGet) {
          method = 'GET';
          body = null;
          headers = {
            for (final e in headers.entries)
              if (!e.key.toLowerCase().startsWith('content-')) e.key: e.value,
          };
        }
        chain.add(next);
        url = next;
        continue;
      }
      return _finish(response, spec, watch, url, chain);
    }
  }

  Future<HttpResult> _finish(
    HttpClientResponse response,
    HttpRequestSpec spec,
    Stopwatch watch,
    Uri url,
    List<Uri> chain,
  ) async {
    final builder = BytesBuilder(copy: false);
    var truncated = false;
    await for (final chunk in response) {
      final remaining = spec.maxResponseBytes - builder.length;
      if (chunk.length > remaining) {
        builder.add(chunk.sublist(0, remaining));
        truncated = true;
        break;
      }
      builder.add(chunk);
    }
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) => headers[name] = List<String>.of(values));
    watch.stop();
    return HttpResult(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: headers,
      body: builder.takeBytes(),
      truncated: truncated,
      duration: watch.elapsed,
      finalUrl: url,
      redirects: List<Uri>.unmodifiable(chain),
    );
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}
