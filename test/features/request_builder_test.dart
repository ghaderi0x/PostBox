import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/http/domain/request_builder.dart';
import 'package:postbox/features/requests/domain/request_models.dart';
import 'package:postbox/features/http/domain/http_engine.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';

void main() {
  const builder = RequestBuilder();
  const settings = AppSettings();
  final empty = VariableResolver();

  RequestModel req({
    String url = 'https://api.test/users',
    String method = 'GET',
    List<KeyValue> params = const <KeyValue>[],
    List<KeyValue> headers = const <KeyValue>[],
    BodyType bodyType = BodyType.none,
    String body = '',
    String bodyAux = '',
    List<KeyValue> form = const <KeyValue>[],
    AuthConfig auth = const AuthConfig(),
  }) => RequestModel(
    id: 'r1',
    method: method,
    url: url,
    params: params,
    headers: headers,
    bodyType: bodyType,
    body: body,
    bodyAux: bodyAux,
    formFields: form,
    auth: auth,
  );

  Future<RequestBuildException> failure(
    RequestModel r, [
    VariableResolver? v,
    AppSettings s = settings,
  ]) async {
    try {
      await builder.build(r, v ?? empty, s);
    } on RequestBuildException catch (e) {
      return e;
    }
    fail('expected a RequestBuildException');
  }

  test('adds scheme: https by default, http for localhost', () async {
    expect(
      (await builder.build(
        req(url: 'api.test/x'),
        empty,
        settings,
      )).spec.url.toString(),
      'https://api.test/x',
    );
    expect(
      (await builder.build(
        req(url: 'localhost:8080/x'),
        empty,
        settings,
      )).spec.url.scheme,
      'http',
    );
    expect(
      (await builder.build(
        req(url: '192.168.1.5/x'),
        empty,
        settings,
      )).spec.url.scheme,
      'http',
    );
  });

  test(
    'enabled params are encoded and appended to an existing query',
    () async {
      final b = await builder.build(
        req(
          url: 'https://api.test/s?x=1',
          params: const <KeyValue>[
            KeyValue(key: 'q', value: 'a b&c'),
            KeyValue(key: 'off', value: 'z', enabled: false),
            KeyValue(key: '', value: 'blank'),
          ],
        ),
        empty,
        settings,
      );
      expect(b.spec.url.toString(), 'https://api.test/s?x=1&q=a+b%26c');
    },
  );

  test('variables are resolved before encoding', () async {
    final vars = VariableResolver(
      environment: <Variable>[
        const Variable(id: '1', key: 'host', value: 'api.test'),
        const Variable(id: '2', key: 'term', value: 'x y'),
      ],
    );
    final b = await builder.build(
      req(
        url: 'https://{{host}}/s',
        params: const <KeyValue>[KeyValue(key: 'q', value: '{{term}}')],
      ),
      vars,
      settings,
    );
    expect(b.spec.url.toString(), 'https://api.test/s?q=x+y');
  });

  test(
    'unresolved variable in the URL is an error naming the variable',
    () async {
      final e = await failure(req(url: '{{base}}/x'));
      expect(e.code, 'unresolved_url');
      expect(e.detail, contains('base'));
    },
  );

  test('bad URLs', () async {
    expect((await failure(req(url: '  '))).code, 'empty_url');
    expect(
      (await failure(req(url: 'ftp://x.test/a'))).code,
      'unsupported_scheme',
    );
  });

  test('bearer, basic and api key auth', () async {
    final bearer = await builder.build(
      req(
        auth: const AuthConfig(type: AuthType.bearer, token: 'tok'),
      ),
      empty,
      settings,
    );
    expect(bearer.spec.headers['Authorization'], 'Bearer tok');

    final basic = await builder.build(
      req(
        auth: const AuthConfig(
          type: AuthType.basic,
          username: 'u',
          password: 'p',
        ),
      ),
      empty,
      settings,
    );
    expect(
      basic.spec.headers['Authorization'],
      'Basic ${base64.encode(utf8.encode('u:p'))}',
    );

    final keyHeader = await builder.build(
      req(
        auth: const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'X-Key',
          apiKeyValue: 'k1',
        ),
      ),
      empty,
      settings,
    );
    expect(keyHeader.spec.headers['X-Key'], 'k1');

    final keyQuery = await builder.build(
      req(
        auth: const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'key',
          apiKeyValue: 'k 2',
          apiKeyInHeader: false,
        ),
      ),
      empty,
      settings,
    );
    expect(keyQuery.spec.url.queryParameters['key'], 'k 2');
  });

  test(
    'preview masks credentials and secret variables; the real request keeps them',
    () async {
      final vars = VariableResolver(
        environment: <Variable>[
          const Variable(id: '1', key: 'tok', value: 'S3CRET', secret: true),
        ],
      );
      final b = await builder.build(
        req(
          headers: const <KeyValue>[
            KeyValue(key: 'X-Custom', value: '{{tok}}'),
          ],
          auth: const AuthConfig(type: AuthType.bearer, token: '{{tok}}'),
        ),
        vars,
        settings,
      );
      expect(b.spec.headers['Authorization'], 'Bearer S3CRET');
      expect(b.spec.headers['X-Custom'], 'S3CRET');
      final shown = b.preview.headers
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
      expect(shown.contains('S3CRET'), isFalse);
      expect(shown.contains('Authorization: ••••'), isTrue);
    },
  );

  test('json body sets content type; user content type wins', () async {
    final a = await builder.build(
      req(method: 'POST', bodyType: BodyType.json, body: '{"a":1}'),
      empty,
      settings,
    );
    expect(a.spec.headers['Content-Type'], startsWith('application/json'));
    expect(utf8.decode(a.spec.body!), '{"a":1}');

    final b = await builder.build(
      req(
        method: 'POST',
        bodyType: BodyType.json,
        body: '{}',
        headers: const <KeyValue>[
          KeyValue(key: 'content-type', value: 'application/vnd.api+json'),
        ],
      ),
      empty,
      settings,
    );
    expect(
      b.spec.headers.entries
          .where((e) => e.key.toLowerCase() == 'content-type')
          .single
          .value,
      'application/vnd.api+json',
    );
  });

  test('form urlencoded body', () async {
    final b = await builder.build(
      req(
        method: 'POST',
        bodyType: BodyType.formUrlEncoded,
        form: const <KeyValue>[
          KeyValue(key: 'a', value: '1 2'),
          KeyValue(key: 'b', value: 'x&y'),
        ],
      ),
      empty,
      settings,
    );
    expect(utf8.decode(b.spec.body!), 'a=1+2&b=x%26y');
    expect(b.spec.headers['Content-Type'], 'application/x-www-form-urlencoded');
  });

  test(
    'multipart: boundary is generated and a user Content-Type is replaced',
    () async {
      final dir = await Directory.systemTemp.createTemp('postbox_mp');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/note.txt')
        ..writeAsStringSync('hello file');
      final b = await builder.build(
        req(
          method: 'POST',
          bodyType: BodyType.multipart,
          headers: const <KeyValue>[
            KeyValue(
              key: 'Content-Type',
              value: 'multipart/form-data; boundary=evil',
            ),
          ],
          form: <KeyValue>[
            const KeyValue(key: 'a', value: 'text value'),
            KeyValue(key: 'f', value: file.path, isFile: true),
          ],
        ),
        empty,
        settings,
      );
      final ct = b.spec.headers['Content-Type']!;
      expect(
        ct,
        startsWith('multipart/form-data; boundary=----PostBoxBoundary'),
      );
      expect(ct.contains('evil'), isFalse);
      final boundary = ct.split('boundary=').last;
      final body = utf8.decode(b.spec.body!);
      expect(
        body,
        contains(
          '--$boundary\r\nContent-Disposition: form-data; name="a"\r\n\r\ntext value\r\n',
        ),
      );
      expect(body, contains('filename="note.txt"'));
      expect(body, contains('hello file'));
      expect(body.endsWith('--$boundary--\r\n'), isTrue);
      expect(b.warnings, contains('content_type_overridden'));
    },
  );

  test('missing multipart file is reported', () async {
    final e = await failure(
      req(
        method: 'POST',
        bodyType: BodyType.multipart,
        form: const <KeyValue>[
          KeyValue(key: 'f', value: '/definitely/not/here.bin', isFile: true),
        ],
      ),
    );
    expect(e.code, 'file_missing');
  });

  test('graphql body', () async {
    final b = await builder.build(
      req(
        method: 'POST',
        bodyType: BodyType.graphql,
        body: '{ me { id } }',
        bodyAux: '{"a":1}',
      ),
      empty,
      settings,
    );
    final decoded =
        jsonDecode(utf8.decode(b.spec.body!)) as Map<String, dynamic>;
    expect(decoded['query'], '{ me { id } }');
    expect(decoded['variables'], <String, dynamic>{'a': 1});
    expect(
      (await failure(
        req(bodyType: BodyType.graphql, body: 'q', bodyAux: '{bad'),
      )).code,
      'graphql_vars_invalid',
    );
  });

  test('request size limit', () async {
    final big = 'x' * (2 * 1024 * 1024);
    final e = await failure(
      req(method: 'POST', bodyType: BodyType.text, body: big),
      empty,
      const AppSettings(maxRequestMb: 1),
    );
    expect(e.code, 'request_too_large');
  });

  test('settings are applied to the spec', () async {
    final b = await builder.build(
      req(),
      empty,
      const AppSettings(
        timeoutSeconds: 7,
        redirectPolicy: RedirectPolicy.sameOrigin,
        maxRedirects: 3,
        proxy: '127.0.0.1:8888',
        maxResponseMb: 2,
        defaultHeaders: <KeyValue>[
          KeyValue(key: 'X-Default', value: 'd'),
          KeyValue(key: 'Accept', value: 'application/json'),
        ],
      ),
    );
    expect(b.spec.timeout, const Duration(seconds: 7));
    expect(b.spec.redirectPolicy, RedirectPolicy.sameOrigin);
    expect(b.spec.maxRedirects, 3);
    expect(b.spec.proxy, '127.0.0.1:8888');
    expect(b.spec.maxResponseBytes, 2 * 1024 * 1024);
    expect(b.spec.allowInvalidCertificates, isFalse);
    expect(b.spec.headers['X-Default'], 'd');
    expect(b.spec.headers['Accept'], 'application/json');
  });

  test('request headers override default headers', () async {
    final b = await builder.build(
      req(
        headers: const <KeyValue>[KeyValue(key: 'X-Default', value: 'mine')],
      ),
      empty,
      const AppSettings(
        defaultHeaders: <KeyValue>[KeyValue(key: 'x-default', value: 'theirs')],
      ),
    );
    expect(
      b.spec.headers.entries
          .where((e) => e.key.toLowerCase() == 'x-default')
          .single
          .value,
      'mine',
    );
  });
}
