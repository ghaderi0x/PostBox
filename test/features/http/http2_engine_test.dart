import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http2/http2.dart' as h2;
import 'package:postbox/features/http/data/io_http_engine.dart';
import 'package:postbox/features/http/domain/cookie_jar.dart';
import 'package:postbox/features/http/domain/http_engine.dart';

/// Self-signed certificate for localhost used only by these tests
/// (test/fixtures, generated with openssl, valid for 100 years).
SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChain('test/fixtures/localhost_cert.pem')
  ..usePrivateKey('test/fixtures/localhost_key.pem');

/// A small HTTP/2 server: echoes method, path and body.
Future<SecureServerSocket> _h2Server() async {
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    _serverContext(),
    supportedProtocols: <String>['h2'],
  );
  server.listen((socket) {
    final conn = h2.ServerTransportConnection.viaSocket(socket);
    conn.incomingStreams.listen((stream) {
      var method = '';
      var path = '';
      final body = BytesBuilder();
      String? clientHeader;
      stream.incomingMessages.listen(
        (m) {
          if (m is h2.HeadersStreamMessage) {
            for (final h in m.headers) {
              final name = utf8.decode(h.name);
              final value = utf8.decode(h.value);
              if (name == ':method') method = value;
              if (name == ':path') path = value;
              if (name == 'x-test') clientHeader = value;
            }
          } else if (m is h2.DataStreamMessage) {
            body.add(m.bytes);
          }
        },
        onDone: () {
          stream.outgoingMessages.add(
            h2.HeadersStreamMessage(<h2.Header>[
              h2.Header.ascii(':status', '200'),
              h2.Header.ascii('content-type', 'text/plain'),
              h2.Header.ascii('set-cookie', 'h2sid=1; Path=/'),
              h2.Header.ascii('x-echo', clientHeader ?? ''),
            ]),
          );
          stream.outgoingMessages.add(
            h2.DataStreamMessage(
              utf8.encode('$method $path ${utf8.decode(body.takeBytes())}'),
              endStream: true,
            ),
          );
        },
      );
    });
  }, onError: (Object _) {});
  return server;
}

/// Whether a Dart TLS server on this machine negotiates "h2" through ALPN.
/// Some platform builds cannot, in which case the end-to-end HTTP/2 tests are
/// skipped (and reported as skipped, not passed).
Future<bool> _serverAlpnWorks() async {
  SecureServerSocket? server;
  try {
    server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _serverContext(),
      supportedProtocols: <String>['h2'],
    );
    server.listen((s) => s.destroy(), onError: (Object _) {});
    final c = await SecureSocket.connect(
      '127.0.0.1',
      server.port,
      supportedProtocols: <String>['h2', 'http/1.1'],
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 5),
    );
    final ok = c.selectedProtocol == 'h2';
    c.destroy();
    return ok;
  } on Object {
    return false;
  } finally {
    await server?.close();
  }
}

Future<void> main() async {
  final alpn = await _serverAlpnWorks();
  void h2test(String name, Future<void> Function() body) => test(
    name,
    body,
    skip: alpn
        ? null
        : 'This platform\'s Dart TLS server does not negotiate h2',
  );
  const engine = IoHttpEngine();
  final closers = <Future<void> Function()>[];

  tearDown(() async {
    for (final c in closers) {
      await c();
    }
    closers.clear();
  });

  Uri url(int port, String path) => Uri.parse('https://localhost:$port$path');

  h2test(
    'GET over HTTP/2 negotiates h2 and returns body, headers and TLS info',
    () async {
      final s = await _h2Server();
      closers.add(() async => s.close());
      final jar = CookieJarImpl();
      final r = await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: url(s.port, '/hello?x=1'),
          headers: const <String, String>{'X-Test': 'abc'},
          preferHttp2: true,
          allowInvalidCertificates: true,
          cookieJar: jar,
        ),
      );
      expect(r.protocol, 'h2');
      expect(r.statusCode, 200);
      expect(r.reasonPhrase, 'OK');
      expect(utf8.decode(r.body), 'GET /hello?x=1 ');
      expect(r.header('x-echo'), 'abc');
      expect(r.tls, isNotNull);
      expect(r.tls!.subject, contains('localhost'));
      expect(r.tls!.sha1.length, 40);
      expect(r.timings.connect, isNotNull);
      expect(jar.all().single.name, 'h2sid');
    },
  );

  h2test('POST body is sent over HTTP/2', () async {
    final s = await _h2Server();
    closers.add(() async => s.close());
    final r = await engine.send(
      HttpRequestSpec(
        method: 'POST',
        url: url(s.port, '/submit'),
        body: Uint8List.fromList(utf8.encode('{"a":1}')),
        headers: const <String, String>{'Content-Type': 'application/json'},
        preferHttp2: true,
        allowInvalidCertificates: true,
      ),
    );
    expect(r.protocol, 'h2');
    expect(utf8.decode(r.body), 'POST /submit {"a":1}');
  });

  h2test('response size limit truncates over HTTP/2', () async {
    final s = await _h2Server();
    closers.add(() async => s.close());
    final r = await engine.send(
      HttpRequestSpec(
        method: 'POST',
        url: url(s.port, '/big'),
        body: Uint8List.fromList(utf8.encode('x' * 5000)),
        preferHttp2: true,
        allowInvalidCertificates: true,
        maxResponseBytes: 100,
      ),
    );
    expect(r.body.length, 100);
    expect(r.truncated, isTrue);
  });

  test('falls back to HTTP/1.1 when the server does not offer h2', () async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      _serverContext(),
    );
    closers.add(() => server.close(force: true));
    server.listen((req) async {
      req.response.write('plain http1');
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: url(server.port, '/'),
        preferHttp2: true,
        allowInvalidCertificates: true,
      ),
    );
    expect(r.protocol, 'HTTP/1.1');
    expect(utf8.decode(r.body), 'plain http1');
    expect(r.tls, isNotNull);
  });

  test(
    'a self-signed certificate is rejected unless allowed or trusted',
    () async {
      final s = await _h2Server();
      closers.add(() async => s.close());
      expect(
        () => engine.send(
          HttpRequestSpec(
            method: 'GET',
            url: url(s.port, '/'),
            preferHttp2: true,
          ),
        ),
        throwsA(
          isA<HttpFailure>().having((f) => f.kind, 'kind', HttpFailureKind.tls),
        ),
      );
    },
  );

  h2test(
    'a custom CA makes the self-signed certificate trusted (HTTP/2 and HTTP/1.1)',
    () async {
      final s = await _h2Server();
      closers.add(() async => s.close());
      final viaH2 = await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: url(s.port, '/ca'),
          preferHttp2: true,
          caCertPath: 'test/fixtures/localhost_cert.pem',
        ),
      );
      expect(viaH2.protocol, 'h2');
      expect(viaH2.statusCode, 200);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        _serverContext(),
      );
      closers.add(() => server.close(force: true));
      server.listen((req) async {
        await req.response.close();
      });
      final viaH1 = await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: url(server.port, '/'),
          caCertPath: 'test/fixtures/localhost_cert.pem',
        ),
      );
      expect(viaH1.statusCode, 200);
      expect(viaH1.protocol, 'HTTP/1.1');
    },
  );

  test('a custom CA trusts a self-signed HTTPS server over HTTP/1.1', () async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      _serverContext(),
    );
    closers.add(() => server.close(force: true));
    server.listen((req) async {
      req.response.write('trusted');
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: url(server.port, '/'),
        caCertPath: 'test/fixtures/localhost_cert.pem',
      ),
    );
    expect(r.statusCode, 200);
    expect(utf8.decode(r.body), 'trusted');
    expect(r.protocol, 'HTTP/1.1');
  });

  test(
    'mutual TLS: the client certificate is presented and required',
    () async {
      final ctx = _serverContext()
        ..setTrustedCertificates('test/fixtures/localhost_cert.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        ctx,
        requestClientCertificate: true,
      );
      closers.add(() => server.close(force: true));
      final seen = <String?>[];
      server.listen((req) async {
        seen.add(req.certificate?.subject);
        req.response.write('hello client');
        await req.response.close();
      });
      final withCert = await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: url(server.port, '/'),
          caCertPath: 'test/fixtures/localhost_cert.pem',
          clientCertPath: 'test/fixtures/localhost_cert.pem',
          clientKeyPath: 'test/fixtures/localhost_key.pem',
        ),
      );
      expect(withCert.statusCode, 200);
      expect(seen.single, contains('localhost'));

      await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: url(server.port, '/'),
          caCertPath: 'test/fixtures/localhost_cert.pem',
        ),
      );
      expect(seen.last, isNull);
    },
  );

  h2test('cancelling aborts an HTTP/2 request', () async {
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _serverContext(),
      supportedProtocols: <String>['h2'],
    );
    closers.add(() async => server.close());
    server.listen((socket) {
      // Accepts the connection but never answers.
      final conn = h2.ServerTransportConnection.viaSocket(socket);
      conn.incomingStreams.listen((_) {});
    }, onError: (Object _) {});
    final token = CancelToken();
    final future = engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: url(server.port, '/'),
        preferHttp2: true,
        allowInvalidCertificates: true,
        timeout: const Duration(seconds: 20),
      ),
      cancel: token,
    );
    expectLater(future, throwsA(isA<HttpFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    token.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
}
