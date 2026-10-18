import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';

import '../../core/app_info.dart';
import '../http/domain/http_engine.dart';
import '../requests/domain/request_models.dart';

/// Supported flow: Authorization Code with PKCE (S256) and refresh tokens.
/// Redirect: loopback `http://127.0.0.1:<port>/callback` on desktop, the
/// custom scheme `com.uniqueone.postbox:/oauth2redirect` on Android.
/// Not supported: implicit, password, client-credentials, device flows.
class OAuthException implements Exception {
  const OAuthException(this.code, [this.detail = '']);
  final String code;
  final String detail;

  @override
  String toString() => 'OAuthException($code${detail.isEmpty ? '' : ': $detail'})';
}

class OAuthTokens {
  const OAuthTokens({required this.accessToken, this.refreshToken, this.expiresAtMs = 0});
  final String accessToken;
  final String? refreshToken;
  final int expiresAtMs;
}

class PkcePair {
  const PkcePair(this.verifier, this.challenge);
  final String verifier;
  final String challenge;
}

const String _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

String _randomString(int length) {
  final rng = Random.secure();
  return List<String>.generate(length, (_) => _unreserved[rng.nextInt(_unreserved.length)]).join();
}

PkcePair generatePkce() {
  final verifier = _randomString(64);
  final digest = sha256.convert(ascii.encode(verifier)).bytes;
  final challenge = base64Url.encode(digest).replaceAll('=', '');
  return PkcePair(verifier, challenge);
}

String generateState() => _randomString(32);

class RedirectSession {
  RedirectSession(this.redirectUri, this.callback, this._close);
  final Uri redirectUri;
  final Future<Uri> callback;
  final Future<void> Function() _close;
  Future<void> close() => _close();
}

abstract interface class RedirectReceiver {
  Future<RedirectSession> start();
}

class LoopbackRedirectReceiver implements RedirectReceiver {
  const LoopbackRedirectReceiver();

  static const String _page =
      '<!doctype html><meta charset="utf-8"><title>PostBox</title>'
      '<p style="font-family:sans-serif">Authorization finished. You can close this tab and return to PostBox.</p>';

  @override
  Future<RedirectSession> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<Uri>();
    server.listen((req) async {
      if (req.uri.path == '/callback') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_page);
        await req.response.close();
        if (!completer.isCompleted) completer.complete(req.requestedUri);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    });
    return RedirectSession(
      Uri.parse('http://127.0.0.1:${server.port}/callback'),
      completer.future,
      () async {
        await server.close(force: true);
      },
    );
  }
}

class AppLinkRedirectReceiver implements RedirectReceiver {
  const AppLinkRedirectReceiver();

  @override
  Future<RedirectSession> start() async {
    final completer = Completer<Uri>();
    final sub = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme == oauthCustomScheme && !completer.isCompleted) {
        completer.complete(uri);
      }
    });
    return RedirectSession(
      Uri.parse(oauthAndroidRedirect),
      completer.future,
      () async {
        await sub.cancel();
      },
    );
  }
}

typedef UrlLauncher = Future<bool> Function(Uri url);

class OAuthService {
  OAuthService({
    required HttpEngine engine,
    required UrlLauncher launcher,
    RedirectReceiver? receiver,
    this.timeout = const Duration(minutes: 5),
  })  : _engine = engine,
        _launcher = launcher,
        _receiver = receiver ??
            (Platform.isAndroid ? const AppLinkRedirectReceiver() : const LoopbackRedirectReceiver());

  final HttpEngine _engine;
  final UrlLauncher _launcher;
  final RedirectReceiver _receiver;
  final Duration timeout;

  static bool _isSecureEndpoint(Uri u) {
    if (u.scheme == 'https') return true;
    return u.scheme == 'http' && (u.host == 'localhost' || u.host == '127.0.0.1');
  }

  Uri _endpoint(String raw, String code) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) throw OAuthException(code);
    if (!_isSecureEndpoint(u)) throw const OAuthException('insecure_endpoint');
    return u;
  }

  Future<OAuthTokens> authorize(AuthConfig c) async {
    if (c.clientId.trim().isEmpty) throw const OAuthException('missing_client_id');
    final authUrl = _endpoint(c.authUrl, 'invalid_auth_url');
    final tokenUrl = _endpoint(c.tokenUrl, 'invalid_token_url');

    final pkce = generatePkce();
    final state = generateState();
    final session = await _receiver.start();
    try {
      final query = <String, String>{
        ...authUrl.queryParameters,
        'response_type': 'code',
        'client_id': c.clientId.trim(),
        'redirect_uri': session.redirectUri.toString(),
        'state': state,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        if (c.scope.trim().isNotEmpty) 'scope': c.scope.trim(),
      };
      final launched = await _launcher(authUrl.replace(queryParameters: query));
      if (!launched) throw const OAuthException('browser_failed');

      final Uri callback;
      try {
        callback = await session.callback.timeout(timeout);
      } on TimeoutException {
        throw const OAuthException('timeout');
      }
      final err = callback.queryParameters['error'];
      if (err != null) throw OAuthException('provider_error', err);
      if (callback.queryParameters['state'] != state) {
        throw const OAuthException('state_mismatch');
      }
      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) throw const OAuthException('missing_code');

      return _tokenRequest(tokenUrl, <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': session.redirectUri.toString(),
        'client_id': c.clientId.trim(),
        'code_verifier': pkce.verifier,
        if (c.clientSecret.isNotEmpty) 'client_secret': c.clientSecret,
      });
    } finally {
      await session.close();
    }
  }

  Future<OAuthTokens> refresh(AuthConfig c) async {
    if (c.refreshToken.isEmpty) throw const OAuthException('no_refresh_token');
    final tokenUrl = _endpoint(c.tokenUrl, 'invalid_token_url');
    final t = await _tokenRequest(tokenUrl, <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': c.refreshToken,
      'client_id': c.clientId.trim(),
      if (c.clientSecret.isNotEmpty) 'client_secret': c.clientSecret,
    });
    // Providers may omit a new refresh token; keep the old one then.
    return OAuthTokens(
      accessToken: t.accessToken,
      refreshToken: t.refreshToken ?? c.refreshToken,
      expiresAtMs: t.expiresAtMs,
    );
  }

  Future<OAuthTokens> _tokenRequest(Uri url, Map<String, String> form) async {
    final body = form.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final HttpResult res;
    try {
      res = await _engine.send(HttpRequestSpec(
        method: 'POST',
        url: url,
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: Uint8List.fromList(utf8.encode(body)),
        timeout: const Duration(seconds: 30),
        redirectPolicy: RedirectPolicy.never,
        maxResponseBytes: 1024 * 1024,
      ));
    } on HttpFailure catch (e) {
      throw OAuthException('token_request_failed', e.kind.name);
    }
    Map<String, dynamic> json;
    try {
      final d = jsonDecode(utf8.decode(res.body, allowMalformed: true));
      json = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on FormatException {
      json = <String, dynamic>{};
    }
    if (res.statusCode < 200 || res.statusCode >= 300 || json['error'] != null) {
      throw OAuthException('token_error', '${json['error'] ?? res.statusCode}');
    }
    final access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw const OAuthException('token_response_invalid');
    }
    final expiresIn = json['expires_in'];
    final seconds = expiresIn is num ? expiresIn.toInt() : 0;
    return OAuthTokens(
      accessToken: access,
      refreshToken: json['refresh_token'] is String ? json['refresh_token'] as String : null,
      expiresAtMs: seconds > 0
          ? DateTime.now().millisecondsSinceEpoch + seconds * 1000
          : 0,
    );
  }
}
