import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/app_info.dart';
import '../../../core/model/key_value.dart';
import '../../../core/util/redact.dart';
import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';
import '../../settings/domain/app_settings.dart';
import 'cookie_jar.dart';
import 'http_engine.dart';

class RequestBuildException implements Exception {
  const RequestBuildException(this.code, [this.detail = '']);

  /// Stable machine-readable code, mapped to localized text by the UI.
  final String code;
  final String detail;

  @override
  String toString() =>
      'RequestBuildException($code${detail.isEmpty ? '' : ': $detail'})';
}

/// What will be sent, with secrets masked. Safe to show and log.
class RequestPreview {
  const RequestPreview({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyPreview,
  });

  final String method;
  final String url;
  final List<MapEntry<String, String>> headers;
  final String bodyPreview;
}

class BuiltRequest {
  const BuiltRequest({
    required this.spec,
    required this.preview,
    required this.unresolved,
    required this.warnings,
  });

  final HttpRequestSpec spec;
  final RequestPreview preview;
  final Set<String> unresolved;
  final List<String> warnings;
}

class _Parts {
  _Parts(
    this.url,
    this.headers,
    this.bodyText,
    this.multipart,
    this.binaryPath,
  );
  String url;
  final Map<String, String> headers;
  String? bodyText;
  List<KeyValue>? multipart;

  /// Path of the file sent as the whole body ([BodyType.binary]).
  String? binaryPath;
}

/// Turns a [RequestModel] plus variables and settings into an executable
/// [HttpRequestSpec]. Pure apart from reading multipart files.
class RequestBuilder {
  const RequestBuilder();

  static const int _previewBodyLimit = 2000;

  Future<BuiltRequest> build(
    RequestModel r,
    VariableResolver vars,
    AppSettings settings, {
    CookieJar? cookieJar,
    String? clientKeyPassword,
  }) async {
    final unresolved = <String>{};
    final warnings = <String>[];

    final real = _materialize(
      r,
      vars,
      settings.defaultHeaders,
      mask: false,
      unresolved: unresolved,
      warnings: warnings,
    );
    final masked = _materialize(
      r,
      vars,
      settings.defaultHeaders,
      mask: true,
      unresolved: <String>{},
      warnings: <String>[],
    );

    if (real.url.contains('{{')) {
      throw RequestBuildException('unresolved_url', unresolved.join(', '));
    }
    final uri = _parseUri(real.url);
    var body = Uint8List(0);
    var hasBody = false;
    final headers = Map<String, String>.of(real.headers);
    if (real.multipart != null) {
      final enc = await _encodeMultipart(real.multipart!, vars);
      body = enc.$1;
      hasBody = true;
      headers.removeWhere((k, _) => k.toLowerCase() == 'content-type');
      headers['Content-Type'] = 'multipart/form-data; boundary=${enc.$2}';
    } else if (real.binaryPath != null) {
      body = await _readBinary(
        real.binaryPath!,
        settings.maxRequestBytes,
        settings.maxRequestMb,
      );
      hasBody = true;
    } else if (real.bodyText != null) {
      body = Uint8List.fromList(utf8.encode(real.bodyText!));
      hasBody = true;
    }
    if (body.length > settings.maxRequestBytes) {
      throw RequestBuildException(
        'request_too_large',
        '${settings.maxRequestMb}',
      );
    }

    final spec = HttpRequestSpec(
      method: r.method.trim().isEmpty ? 'GET' : r.method.trim().toUpperCase(),
      url: uri,
      headers: headers,
      body: hasBody ? body : null,
      timeout: Duration(seconds: settings.timeoutSeconds),
      redirectPolicy: settings.redirectPolicy,
      maxRedirects: settings.maxRedirects,
      maxResponseBytes: settings.maxResponseBytes,
      proxy: settings.proxy.isEmpty ? null : settings.proxy,
      allowInvalidCertificates: settings.allowInvalidCertificates,
      cookieJar: settings.useCookieJar ? cookieJar : null,
      preferHttp2: settings.httpVersion == HttpVersionPref.auto,
      clientCertPath: settings.clientCertPath.isEmpty
          ? null
          : settings.clientCertPath,
      clientKeyPath: settings.clientKeyPath.isEmpty
          ? null
          : settings.clientKeyPath,
      clientKeyPassword: (clientKeyPassword ?? '').isEmpty
          ? null
          : clientKeyPassword,
      caCertPath: settings.caCertPath.isEmpty ? null : settings.caCertPath,
    );

    final bodyPreview = real.multipart != null
        ? '[multipart/form-data: ${real.multipart!.length} part(s)]'
        : (real.binaryPath != null
              ? '[binary file: ${real.binaryPath!.split(RegExp(r'[\\/]')).last}, ${body.length} bytes]'
              : (masked.bodyText ?? ''));
    final preview = RequestPreview(
      method: spec.method,
      url: masked.url,
      headers: masked.headers.entries
          .map(
            (e) => MapEntry<String, String>(
              e.key,
              Redactor.headerValue(e.key, e.value),
            ),
          )
          .toList(),
      bodyPreview: bodyPreview.length > _previewBodyLimit
          ? '${bodyPreview.substring(0, _previewBodyLimit)}…'
          : bodyPreview,
    );
    return BuiltRequest(
      spec: spec,
      preview: preview,
      unresolved: unresolved,
      warnings: warnings,
    );
  }

  _Parts _materialize(
    RequestModel r,
    VariableResolver vars,
    List<KeyValue> defaultHeaders, {
    required bool mask,
    required Set<String> unresolved,
    required List<String> warnings,
  }) {
    String res(String s) {
      final x = vars.resolve(s, maskSecrets: mask);
      unresolved.addAll(x.unresolved);
      return x.text;
    }

    var url = res(r.url.trim());
    if (url.isEmpty) throw const RequestBuildException('empty_url');
    url = _ensureScheme(url);

    final query = <String>[];
    for (final p in r.params) {
      if (!p.enabled || p.key.trim().isEmpty) continue;
      query.add(
        '${Uri.encodeQueryComponent(res(p.key))}=${Uri.encodeQueryComponent(res(p.value))}',
      );
    }

    final headers = <String, String>{
      'Accept': '*/*',
      'User-Agent': 'PostBox/$appVersion',
    };
    void setHeader(String k, String v) {
      headers.removeWhere((e, _) => e.toLowerCase() == k.toLowerCase());
      headers[k] = v;
    }

    // Settings > Requests > Default headers, overridden by the request itself.
    for (final h in defaultHeaders) {
      if (!h.enabled || h.key.trim().isEmpty) continue;
      setHeader(res(h.key.trim()), res(h.value));
    }
    for (final h in r.headers) {
      if (!h.enabled || h.key.trim().isEmpty) continue;
      setHeader(res(h.key.trim()), res(h.value));
    }

    // Authentication.
    final a = r.auth;
    String secret(String raw) => mask ? Redactor.mask : res(raw);
    switch (a.type) {
      case AuthType.none:
      case AuthType.inherit:
        // `inherit` is resolved by the executor before building; if nothing
        // above the request defines auth, nothing is sent.
        break;
      case AuthType.basic:
        final user = res(a.username);
        final pass = secret(a.password);
        final cred = base64.encode(utf8.encode('$user:$pass'));
        setHeader(
          'Authorization',
          mask ? 'Basic ${Redactor.mask}' : 'Basic $cred',
        );
      case AuthType.bearer:
        if (a.token.isNotEmpty) {
          setHeader('Authorization', 'Bearer ${secret(a.token)}');
        }
      case AuthType.apiKey:
        final name = res(a.apiKeyName.trim());
        if (name.isNotEmpty && a.apiKeyValue.isNotEmpty) {
          if (a.apiKeyInHeader) {
            setHeader(name, secret(a.apiKeyValue));
          } else {
            query.add(
              '${Uri.encodeQueryComponent(name)}=${Uri.encodeQueryComponent(secret(a.apiKeyValue))}',
            );
          }
        }
      case AuthType.oauth2:
        if (a.accessToken.isNotEmpty) {
          setHeader('Authorization', 'Bearer ${secret(a.accessToken)}');
        } else {
          warnings.add('oauth_no_token');
        }
    }

    if (query.isNotEmpty) {
      final hash = url.indexOf('#');
      final frag = hash >= 0 ? url.substring(hash) : '';
      var core = hash >= 0 ? url.substring(0, hash) : url;
      core += core.contains('?')
          ? (core.endsWith('?') || core.endsWith('&') ? '' : '&')
          : '?';
      url = core + query.join('&') + frag;
    }

    String? bodyText;
    List<KeyValue>? multipart;
    String? binaryPath;
    switch (r.bodyType) {
      case BodyType.none:
        break;
      case BodyType.json:
        bodyText = res(r.body);
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'application/json; charset=utf-8';
        }
      case BodyType.text:
        bodyText = res(r.body);
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'text/plain; charset=utf-8';
        }
      case BodyType.raw:
        bodyText = res(r.body);
        if (!_hasHeader(headers, 'content-type')) {
          final ct = r.bodyAux.trim();
          headers['Content-Type'] = ct.isEmpty
              ? 'text/plain; charset=utf-8'
              : res(ct);
        }
      case BodyType.formUrlEncoded:
        bodyText = r.formFields
            .where((f) => f.enabled && f.key.trim().isNotEmpty)
            .map(
              (f) =>
                  '${Uri.encodeQueryComponent(res(f.key))}=${Uri.encodeQueryComponent(res(f.value))}',
            )
            .join('&');
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
      case BodyType.multipart:
        multipart = r.formFields
            .where((f) => f.enabled && f.key.trim().isNotEmpty)
            .map(
              (f) => f.copyWith(
                key: res(f.key),
                value: f.isFile ? f.value : res(f.value),
              ),
            )
            .toList();
        if (_hasHeader(headers, 'content-type')) {
          warnings.add('content_type_overridden');
        }
        headers['Content-Type'] = 'multipart/form-data; boundary=preview';
      case BodyType.binary:
        binaryPath = res(r.body).trim();
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'application/octet-stream';
        }
      case BodyType.graphql:
        Object? variables;
        final rawVars = res(r.bodyAux).trim();
        if (rawVars.isNotEmpty) {
          try {
            variables = jsonDecode(rawVars);
          } on FormatException {
            throw const RequestBuildException('graphql_vars_invalid');
          }
        }
        bodyText = jsonEncode(<String, dynamic>{
          'query': res(r.body),
          'variables': ?variables,
        });
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'application/json; charset=utf-8';
        }
    }

    return _Parts(url, headers, bodyText, multipart, binaryPath);
  }

  bool _hasHeader(Map<String, String> h, String lower) =>
      h.keys.any((k) => k.toLowerCase() == lower);

  Uri _parseUri(String url) {
    final Uri u;
    try {
      u = Uri.parse(url);
    } on FormatException {
      throw RequestBuildException('invalid_url', url);
    }
    if (!u.hasScheme || (u.scheme != 'http' && u.scheme != 'https')) {
      throw RequestBuildException('unsupported_scheme', u.scheme);
    }
    if (u.host.isEmpty) throw const RequestBuildException('missing_host');
    return u;
  }

  /// Adds a scheme when the user omitted one: http for local/private hosts,
  /// https otherwise.
  String _ensureScheme(String url) {
    if (RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://').hasMatch(url)) return url;
    final host = url.split(RegExp(r'[/:?#]')).first;
    final local =
        host == 'localhost' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.endsWith('.local');
    return '${local ? 'http' : 'https'}://$url';
  }

  Future<Uint8List> _readBinary(String path, int maxBytes, int maxMb) async {
    if (path.isEmpty) throw const RequestBuildException('file_missing', '');
    final file = File(path);
    if (!await file.exists()) throw RequestBuildException('file_missing', path);
    if (await file.length() > maxBytes) {
      throw RequestBuildException('request_too_large', '$maxMb');
    }
    return file.readAsBytes();
  }

  Future<(Uint8List, String)> _encodeMultipart(
    List<KeyValue> parts,
    VariableResolver vars,
  ) async {
    final rng = Random.secure();
    final boundary =
        '----PostBoxBoundary${List<int>.generate(12, (_) => rng.nextInt(16)).map((e) => e.toRadixString(16)).join()}';
    final out = BytesBuilder(copy: false);
    void w(String s) => out.add(utf8.encode(s));
    String quote(String s) =>
        s.replaceAll('"', '%22').replaceAll('\r', '').replaceAll('\n', '');

    for (final p in parts) {
      w('--$boundary\r\n');
      if (p.isFile) {
        final path = vars.resolve(p.value).text;
        final file = File(path);
        if (!await file.exists()) {
          throw RequestBuildException('file_missing', path);
        }
        final bytes = await file.readAsBytes();
        final name = path.split(RegExp(r'[\\/]')).last;
        w(
          'Content-Disposition: form-data; name="${quote(p.key)}"; filename="${quote(name)}"\r\n',
        );
        w('Content-Type: application/octet-stream\r\n\r\n');
        out.add(bytes);
        w('\r\n');
      } else {
        w('Content-Disposition: form-data; name="${quote(p.key)}"\r\n\r\n');
        w(p.value);
        w('\r\n');
      }
    }
    w('--$boundary--\r\n');
    return (out.takeBytes(), boundary);
  }
}
