import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/http/data/io_http_engine.dart';
import 'package:postbox/features/http/domain/http_engine.dart';

Future<HttpServer> _serve(FutureOr<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    try {
      await handler(req);
    } on Object {
      // Clients that cancelled or timed out may already be gone.
    }
  });
  return server;
}

Uri _uri(HttpServer s, [String path = '/']) =>
    Uri.parse('http://127.0.0.1:${s.port}$path');

void main() {
  const engine = IoHttpEngine();
  final servers = <HttpServer>[];

  Future<HttpServer> serve(FutureOr<void> Function(HttpRequest) h) async {
    final s = await _serve(h);
    servers.add(s);
    return s;
  }

  tearDown(() async {
    for (final s in servers) {
      await s.close(force: true);
    }
    servers.clear();
  });

  test('GET returns status, headers and body', () async {
    final s = await serve((req) async {
      req.response
        ..statusCode = 200
        ..headers.set('x-test', 'yes')
        ..write('hello');
      await req.response.close();
    });
    final r = await engine.send(HttpRequestSpec(method: 'GET', url: _uri(s)));
    expect(r.statusCode, 200);
    expect(utf8.decode(r.body), 'hello');
    expect(r.headers['x-test'], ['yes']);
    expect(r.truncated, isFalse);
  });

  test('POST sends the body', () async {
    final s = await serve((req) async {
      final data = await utf8.decoder.bind(req).join();
      req.response.write('got:$data');
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'POST',
        url: _uri(s),
        body: Uint8List.fromList(utf8.encode('abc')),
      ),
    );
    expect(utf8.decode(r.body), 'got:abc');
  });

  test('response larger than the limit is truncated', () async {
    final s = await serve((req) async {
      req.response.write('x' * 5000);
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(method: 'GET', url: _uri(s), maxResponseBytes: 100),
    );
    expect(r.body.length, 100);
    expect(r.truncated, isTrue);
  });

  test('timeout produces a timeout failure', () async {
    final s = await serve((req) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await req.response.close();
    });
    expect(
      engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: _uri(s),
          timeout: const Duration(milliseconds: 300),
        ),
      ),
      throwsA(
        isA<HttpFailure>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.timeout,
        ),
      ),
    );
  });

  test('cancel produces a cancelled failure', () async {
    final s = await serve((req) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await req.response.close();
    });
    final token = CancelToken();
    final future = engine.send(
      HttpRequestSpec(method: 'GET', url: _uri(s)),
      cancel: token,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    token.cancel();
    await expectLater(
      future,
      throwsA(
        isA<HttpFailure>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.cancelled,
        ),
      ),
    );
  });

  test('same-origin redirect keeps Authorization', () async {
    final s = await serve((req) async {
      if (req.uri.path == '/start') {
        req.response
          ..statusCode = 302
          ..headers.set('location', '/end');
      } else {
        req.response.write(req.headers.value('authorization') ?? 'none');
      }
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: _uri(s, '/start'),
        headers: const {'Authorization': 'Bearer t'},
      ),
    );
    expect(utf8.decode(r.body), 'Bearer t');
    expect(r.redirects.length, 1);
  });

  test('cross-origin redirect strips Authorization', () async {
    final target = await serve((req) async {
      req.response.write(req.headers.value('authorization') ?? 'none');
      await req.response.close();
    });
    final origin = await serve((req) async {
      req.response
        ..statusCode = 302
        ..headers.set('location', _uri(target).toString());
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: _uri(origin),
        headers: const {'Authorization': 'Bearer secret'},
      ),
    );
    expect(utf8.decode(r.body), 'none');
  });

  test('redirect policy never returns the 3xx response', () async {
    final s = await serve((req) async {
      req.response
        ..statusCode = 302
        ..headers.set('location', '/x');
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: _uri(s),
        redirectPolicy: RedirectPolicy.never,
      ),
    );
    expect(r.statusCode, 302);
  });

  test('redirect loop stops at maxRedirects', () async {
    final s = await serve((req) async {
      req.response
        ..statusCode = 302
        ..headers.set('location', '/loop');
      await req.response.close();
    });
    expect(
      engine.send(
        HttpRequestSpec(method: 'GET', url: _uri(s), maxRedirects: 3),
      ),
      throwsA(
        isA<HttpFailure>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.tooManyRedirects,
        ),
      ),
    );
  });

  test('refused connection maps to a connection failure', () async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = _uri(s);
    await s.close(force: true);
    expect(
      engine.send(HttpRequestSpec(method: 'GET', url: url)),
      throwsA(
        isA<HttpFailure>().having(
          (e) => e.kind,
          'kind',
          HttpFailureKind.connection,
        ),
      ),
    );
  });
}
