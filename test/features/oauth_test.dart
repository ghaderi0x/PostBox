import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/auth/oauth_service.dart';
import 'package:postbox/features/http/data/io_http_engine.dart';
import 'package:postbox/features/requests/domain/request_models.dart';

void main() {
  test('PKCE verifier and S256 challenge', () {
    final p = generatePkce();
    expect(p.verifier.length, 64);
    expect(p.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
    final expected = base64Url.encode(sha256.convert(ascii.encode(p.verifier)).bytes).replaceAll('=', '');
    expect(p.challenge, expected);
    expect(p.challenge.contains('='), isFalse);
    expect(generatePkce().verifier, isNot(p.verifier));
  });

  group('authorization code flow (loopback)', () {
    late HttpServer tokenServer;
    final tokenRequests = <Map<String, String>>[];

    setUp(() async {
      tokenRequests.clear();
      tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      tokenServer.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        final form = Uri.splitQueryString(body);
        tokenRequests.add(form);
        req.response.headers.contentType = ContentType.json;
        if (form['grant_type'] == 'authorization_code' && form['code'] == 'good-code') {
          req.response.write(jsonEncode(<String, dynamic>{
            'access_token': 'AT-1',
            'refresh_token': 'RT-1',
            'expires_in': 3600,
          }));
        } else if (form['grant_type'] == 'refresh_token' && form['refresh_token'] == 'RT-1') {
          req.response.write(jsonEncode(<String, dynamic>{'access_token': 'AT-2', 'expires_in': 60}));
        } else {
          req.response.statusCode = 400;
          req.response.write(jsonEncode(<String, dynamic>{'error': 'invalid_grant'}));
        }
        await req.response.close();
      });
    });

    tearDown(() => tokenServer.close(force: true));

    AuthConfig config({String? tokenUrl, String? authUrl}) => AuthConfig(
          type: AuthType.oauth2,
          authUrl: authUrl ?? 'http://127.0.0.1:${tokenServer.port}/authorize',
          tokenUrl: tokenUrl ?? 'http://127.0.0.1:${tokenServer.port}/token',
          clientId: 'client-1',
          scope: 'read write',
        );

    /// Plays the browser: reads the authorization URL and calls the redirect.
    UrlLauncher browser({String? overrideState, String code = 'good-code', void Function(Uri)? inspect}) {
      return (Uri url) async {
        inspect?.call(url);
        final q = url.queryParameters;
        final redirect = Uri.parse(q['redirect_uri']!).replace(queryParameters: <String, String>{
          'code': code,
          'state': overrideState ?? q['state']!,
        });
        final client = HttpClient();
        unawaited(client.getUrl(redirect).then((r) => r.close()).then((r) => r.drain<void>()).whenComplete(() => client.close()));
        return true;
      };
    }

    test('happy path with PKCE', () async {
      Uri? seen;
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: browser(inspect: (u) => seen = u),
        receiver: const LoopbackRedirectReceiver(),
        timeout: const Duration(seconds: 10),
      );
      final t = await svc.authorize(config());
      expect(t.accessToken, 'AT-1');
      expect(t.refreshToken, 'RT-1');
      expect(t.expiresAtMs, greaterThan(DateTime.now().millisecondsSinceEpoch));

      expect(seen!.queryParameters['response_type'], 'code');
      expect(seen!.queryParameters['client_id'], 'client-1');
      expect(seen!.queryParameters['code_challenge_method'], 'S256');
      expect(seen!.queryParameters['scope'], 'read write');
      expect(seen!.queryParameters['redirect_uri'], startsWith('http://127.0.0.1:'));

      final form = tokenRequests.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'good-code');
      expect(form['client_id'], 'client-1');
      // The verifier must hash to the challenge sent earlier.
      final challenge = base64Url.encode(sha256.convert(ascii.encode(form['code_verifier']!)).bytes).replaceAll('=', '');
      expect(challenge, seen!.queryParameters['code_challenge']);
      expect(form.containsKey('client_secret'), isFalse);
    });

    test('state mismatch is rejected before any token request', () async {
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: browser(overrideState: 'forged'),
        receiver: const LoopbackRedirectReceiver(),
        timeout: const Duration(seconds: 10),
      );
      await expectLater(
        svc.authorize(config()),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'state_mismatch')),
      );
      expect(tokenRequests, isEmpty);
    });

    test('provider error is surfaced', () async {
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: (Uri url) async {
          final q = url.queryParameters;
          final redirect = Uri.parse(q['redirect_uri']!).replace(queryParameters: <String, String>{'error': 'access_denied', 'state': q['state']!});
          final c = HttpClient();
          unawaited(c.getUrl(redirect).then((r) => r.close()).then((r) => r.drain<void>()).whenComplete(() => c.close()));
          return true;
        },
        receiver: const LoopbackRedirectReceiver(),
        timeout: const Duration(seconds: 10),
      );
      await expectLater(
        svc.authorize(config()),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'provider_error')),
      );
    });

    test('token endpoint rejection', () async {
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: browser(code: 'bad-code'),
        receiver: const LoopbackRedirectReceiver(),
        timeout: const Duration(seconds: 10),
      );
      await expectLater(
        svc.authorize(config()),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'token_error')),
      );
    });

    test('times out when the user never comes back', () async {
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: (_) async => true,
        receiver: const LoopbackRedirectReceiver(),
        timeout: const Duration(milliseconds: 300),
      );
      await expectLater(
        svc.authorize(config()),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'timeout')),
      );
    });

    test('refresh keeps the old refresh token when none is returned', () async {
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: (_) async => true,
        receiver: const LoopbackRedirectReceiver(),
      );
      final t = await svc.refresh(config().copyWith(refreshToken: 'RT-1'));
      expect(t.accessToken, 'AT-2');
      expect(t.refreshToken, 'RT-1');
      await expectLater(
        svc.refresh(config()),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'no_refresh_token')),
      );
    });

    test('insecure endpoints are refused', () async {
      final svc = OAuthService(
        engine: const IoHttpEngine(),
        launcher: (_) async => true,
        receiver: const LoopbackRedirectReceiver(),
      );
      await expectLater(
        svc.authorize(config(authUrl: 'http://evil.example/authorize')),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'insecure_endpoint')),
      );
      await expectLater(
        svc.authorize(config().copyWith(clientId: '')),
        throwsA(isA<OAuthException>().having((e) => e.code, 'code', 'missing_client_id')),
      );
    });
  });
}
