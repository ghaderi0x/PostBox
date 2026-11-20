import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/http2.dart' as h2;

import '../domain/http_engine.dart';
import 'raw_exchange.dart';

/// The server did not select `h2` through ALPN. The caller falls back to
/// HTTP/1.1 on a new connection.
class Http2NotNegotiated implements Exception {
  const Http2NotNegotiated();
}

/// A protocol-level HTTP/2 failure (stream reset, malformed response).
class Http2Failure implements Exception {
  const Http2Failure(this.message);
  final String message;

  @override
  String toString() => 'Http2Failure: $message';
}

/// Headers that must not be sent over HTTP/2 (RFC 9113 section 8.2.2) or that
/// HTTP/2 replaces with pseudo-headers.
const Set<String> _connectionSpecific = <String>{
  'host',
  'connection',
  'keep-alive',
  'proxy-connection',
  'transfer-encoding',
  'upgrade',
  'te',
};

/// Performs one request over HTTP/2 on a fresh TLS connection.
///
/// Limits (documented in docs/ARCHITECTURE.md): one connection per request
/// (no multiplexing across requests), no server push, no proxy support, and
/// the response body is streamed with the same size cap as HTTP/1.1.
Future<RawExchange> http2Exchange({
  required String method,
  required Uri url,
  required Map<String, String> headers,
  required Uint8List? body,
  required HttpRequestSpec spec,
  required SecurityContext? context,
  required void Function(void Function()) onAbort,
}) async {
  final sw = Stopwatch()..start();
  final port = url.hasPort ? url.port : 443;
  final SecureSocket socket = await SecureSocket.connect(
    url.host,
    port,
    context: context,
    supportedProtocols: const <String>['h2', 'http/1.1'],
    onBadCertificate: spec.allowInvalidCertificates ? (_) => true : null,
    timeout: spec.timeout,
  );
  onAbort(socket.destroy);

  if (socket.selectedProtocol != 'h2') {
    socket.destroy();
    throw const Http2NotNegotiated();
  }
  final connect = sw.elapsed;

  TlsInfo? tls;
  final cert = socket.peerCertificate;
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

  final transport = h2.ClientTransportConnection.viaSocket(socket);
  var closed = false;
  Future<void> close() async {
    if (closed) return;
    closed = true;
    try {
      // The exchange is over (body read or truncated); drop the connection.
      await transport.terminate().timeout(const Duration(seconds: 1));
    } on Object {
      // The connection is being thrown away; nothing useful to report.
    }
    socket.destroy();
  }

  final authority = url.hasPort && url.port != 443
      ? '${url.host}:${url.port}'
      : url.host;
  final path =
      (url.path.isEmpty ? '/' : url.path) +
      (url.hasQuery ? '?${url.query}' : '');
  final requestHeaders = <h2.Header>[
    h2.Header.ascii(':method', method),
    h2.Header.ascii(':scheme', 'https'),
    h2.Header.ascii(':authority', authority),
    h2.Header(utf8.encode(':path'), utf8.encode(path)),
  ];
  var hasContentLength = false;
  headers.forEach((k, v) {
    final name = k.toLowerCase();
    if (_connectionSpecific.contains(name)) return;
    if (name == 'content-length') hasContentLength = true;
    requestHeaders.add(h2.Header(utf8.encode(name), utf8.encode(v)));
  });
  if (body != null && !hasContentLength) {
    requestHeaders.add(h2.Header.ascii('content-length', '${body.length}'));
  }

  try {
    final stream = transport.makeRequest(
      requestHeaders,
      endStream: body == null,
    );
    if (body != null) {
      stream.outgoingMessages.add(h2.DataStreamMessage(body, endStream: true));
    }

    final bodyController = StreamController<List<int>>();
    final headersReady = Completer<(int, Map<String, List<String>>)>();

    stream.incomingMessages.listen(
      (message) {
        if (message is h2.HeadersStreamMessage) {
          if (headersReady.isCompleted) return; // trailers are ignored
          var status = 0;
          final map = <String, List<String>>{};
          for (final h in message.headers) {
            final name = utf8.decode(h.name, allowMalformed: true);
            final value = utf8.decode(h.value, allowMalformed: true);
            if (name == ':status') {
              status = int.tryParse(value) ?? 0;
            } else if (!name.startsWith(':')) {
              map.putIfAbsent(name, () => <String>[]).add(value);
            }
          }
          // 1xx responses are informational; wait for the final one.
          if (status >= 200) headersReady.complete((status, map));
        } else if (message is h2.DataStreamMessage) {
          if (!bodyController.isClosed) bodyController.add(message.bytes);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!headersReady.isCompleted) {
          headersReady.completeError(Http2Failure('$e'), st);
        }
        if (!bodyController.isClosed) {
          bodyController.addError(Http2Failure('$e'), st);
        }
      },
      onDone: () {
        if (!headersReady.isCompleted) {
          headersReady.completeError(
            const Http2Failure('Connection closed before response headers.'),
          );
        }
        if (!bodyController.isClosed) unawaited(bodyController.close());
      },
      cancelOnError: true,
    );

    final (status, responseHeaders) = await headersReady.future;
    final wait = sw.elapsed - connect;
    return RawExchange(
      status: status,
      reason: reasonPhraseFor(status),
      headers: responseHeaders,
      body: bodyController.stream,
      protocol: 'h2',
      connect: connect,
      wait: wait,
      tls: tls,
      close: close,
    );
  } on Object {
    await close();
    rethrow;
  }
}
