import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/http/data/io_http_engine.dart';
import 'package:postbox/features/http/domain/cookie_jar.dart';
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

  Uri url(HttpServer s, String path) =>
      Uri.parse('http://127.0.0.1:${s.port}$path');

  group('cookie jar', () {
    test('stores Set-Cookie and sends it on the next request', () async {
      final seen = <String?>[];
      final s = await serve((req) async {
        seen.add(req.headers.value('cookie'));
        if (req.uri.path == '/login') {
          req.response.headers.add('set-cookie', 'sid=abc; Path=/; HttpOnly');
          req.response.headers.add('set-cookie', 'theme=dark; Path=/');
        }
        await req.response.close();
      });
      final jar = CookieJarImpl();
      await engine.send(
        HttpRequestSpec(method: 'GET', url: url(s, '/login'), cookieJar: jar),
      );
      await engine.send(
        HttpRequestSpec(method: 'GET', url: url(s, '/next'), cookieJar: jar),
      );
      expect(seen.first, isNull);
      expect(seen.last, contains('sid=abc'));
      expect(seen.last, contains('theme=dark'));
      expect(jar.all().length, 2);
    });

    test('a Cookie header set by the user wins over the jar', () async {
      String? seen;
      final s = await serve((req) async {
        seen = req.headers.value('cookie');
        await req.response.close();
      });
      final jar = CookieJarImpl()
        ..storeFromResponse(url(s, '/'), <String>['sid=fromjar; Path=/']);
      await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: url(s, '/'),
          headers: const <String, String>{'Cookie': 'sid=manual'},
          cookieJar: jar,
        ),
      );
      expect(seen, 'sid=manual');
    });

    test('without a jar nothing is stored or sent', () async {
      String? seen;
      final s = await serve((req) async {
        seen = req.headers.value('cookie');
        req.response.headers.add('set-cookie', 'a=1');
        await req.response.close();
      });
      await engine.send(HttpRequestSpec(method: 'GET', url: url(s, '/')));
      await engine.send(HttpRequestSpec(method: 'GET', url: url(s, '/')));
      expect(seen, isNull);
    });

    test(
      'cookies set during a redirect chain are applied to the next hop',
      () async {
        String? finalCookie;
        final s = await serve((req) async {
          if (req.uri.path == '/start') {
            req.response
              ..statusCode = 302
              ..headers.add('set-cookie', 'hop=1; Path=/')
              ..headers.set('location', '/end');
          } else {
            finalCookie = req.headers.value('cookie');
          }
          await req.response.close();
        });
        final r = await engine.send(
          HttpRequestSpec(
            method: 'GET',
            url: url(s, '/start'),
            cookieJar: CookieJarImpl(),
          ),
        );
        expect(r.statusCode, 200);
        expect(finalCookie, 'hop=1');
      },
    );

    test(
      'a manual Cookie header is not forwarded across origins, the jar of the new host is used',
      () async {
        String? otherSaw;
        final other = await serve((req) async {
          otherSaw = req.headers.value('cookie');
          await req.response.close();
        });
        final first = await serve((req) async {
          req.response
            ..statusCode = 302
            ..headers.set('location', 'http://localhost:${other.port}/');
          await req.response.close();
        });
        final jar = CookieJarImpl()
          ..storeFromResponse(
            Uri.parse('http://localhost:${other.port}/'),
            <String>['k=jar; Path=/'],
          );
        await engine.send(
          HttpRequestSpec(
            method: 'GET',
            url: url(first, '/'),
            headers: const <String, String>{
              'Cookie': 'secret=manual',
              'Authorization': 'Bearer x',
            },
            cookieJar: jar,
          ),
        );
        expect(otherSaw, 'k=jar');
      },
    );
  });

  group('timings and metadata', () {
    test('reports connect, wait and download timings and protocol', () async {
      final s = await serve((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        req.response.write('x' * 1000);
        await req.response.close();
      });
      final r = await engine.send(
        HttpRequestSpec(method: 'GET', url: url(s, '/')),
      );
      expect(r.protocol, 'HTTP/1.1');
      expect(r.tls, isNull);
      expect(r.timings.wait.inMilliseconds, greaterThanOrEqualTo(60));
      expect(r.timings.connect, isNotNull);
      expect(r.duration >= r.timings.wait, isTrue);
      expect(r.timings.redirects, Duration.zero);
    });

    test('redirect time is reported separately', () async {
      final s = await serve((req) async {
        if (req.uri.path == '/a') {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          req.response
            ..statusCode = 302
            ..headers.set('location', '/b');
        }
        await req.response.close();
      });
      final r = await engine.send(
        HttpRequestSpec(method: 'GET', url: url(s, '/a')),
      );
      expect(r.redirects.length, 1);
      expect(r.timings.redirects.inMilliseconds, greaterThanOrEqualTo(50));
    });

    test('preferHttp2 on a plain http URL stays on HTTP/1.1', () async {
      final s = await serve((req) async => req.response.close());
      final r = await engine.send(
        HttpRequestSpec(method: 'GET', url: url(s, '/'), preferHttp2: true),
      );
      expect(r.protocol, 'HTTP/1.1');
    });
  });

  group('TLS configuration errors', () {
    test('a missing client certificate file is a clear tls failure', () async {
      final s = await serve((req) async => req.response.close());
      expect(
        () => engine.send(
          HttpRequestSpec(
            method: 'GET',
            url: url(s, '/'),
            clientCertPath: '/definitely/not/here.pem',
          ),
        ),
        throwsA(
          isA<HttpFailure>().having((f) => f.kind, 'kind', HttpFailureKind.tls),
        ),
      );
    });

    test('a missing CA file is a clear tls failure', () async {
      final s = await serve((req) async => req.response.close());
      expect(
        () => engine.send(
          HttpRequestSpec(
            method: 'GET',
            url: url(s, '/'),
            caCertPath: '/nope/ca.pem',
          ),
        ),
        throwsA(
          isA<HttpFailure>().having((f) => f.kind, 'kind', HttpFailureKind.tls),
        ),
      );
    });

    test('a file that is not a certificate is rejected', () async {
      final s = await serve((req) async => req.response.close());
      final f = File(
        '${Directory.systemTemp.path}/postbox_bad_ca_${DateTime.now().microsecondsSinceEpoch}.pem',
      )..writeAsStringSync('this is not a certificate');
      addTearDown(() => f.delete());
      expect(
        () => engine.send(
          HttpRequestSpec(method: 'GET', url: url(s, '/'), caCertPath: f.path),
        ),
        throwsA(
          isA<HttpFailure>().having((e) => e.kind, 'kind', HttpFailureKind.tls),
        ),
      );
    });
  });

  test('body of HttpResult is decodable after cookies are processed', () async {
    final s = await serve((req) async {
      req.response
        ..headers.add('set-cookie', 'a=1')
        ..write('ok');
      await req.response.close();
    });
    final r = await engine.send(
      HttpRequestSpec(
        method: 'GET',
        url: url(s, '/'),
        cookieJar: CookieJarImpl(),
      ),
    );
    expect(utf8.decode(r.body), 'ok');
  });
}
