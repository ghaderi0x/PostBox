import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/collections/domain/collection_models.dart';
import 'package:postbox/features/import_export/curl.dart';
import 'package:postbox/features/requests/domain/request_models.dart';

void main() {
  group('tokenizeShell', () {
    test('quotes, escapes and continuations', () {
      expect(tokenizeShell(r'''curl -H 'A: b c' "d e" f\ g'''), <String>[
        'curl',
        '-H',
        'A: b c',
        'd e',
        'f g',
      ]);
      expect(tokenizeShell('curl \\\n  -X GET url'), <String>[
        'curl',
        '-X',
        'GET',
        'url',
      ]);
      expect(tokenizeShell(r'''echo "a \"q\" b"'''), <String>[
        'echo',
        'a "q" b',
      ]);
      expect(tokenizeShell(r"echo $'a\nb'"), <String>['echo', 'a\nb']);
    });

    test('unterminated quote returns null', () {
      expect(tokenizeShell("curl 'abc"), isNull);
      expect(tokenizeShell('curl "abc'), isNull);
    });
  });

  group('parseCurl', () {
    test('typical JSON POST with bearer auth', () {
      final r = parseCurl(
        "curl -X POST 'https://api.test/v1/items?x=1' "
        "-H 'Content-Type: application/json' -H 'Authorization: Bearer abc' -d '{\"a\":1}'",
      ).request!;
      expect(r.method, 'POST');
      expect(r.url, 'https://api.test/v1/items');
      expect(r.params.single.key, 'x');
      expect(r.params.single.value, '1');
      expect(r.bodyType, BodyType.json);
      expect(r.body, '{"a":1}');
      expect(r.auth.type, AuthType.bearer);
      expect(r.auth.token, 'abc');
      expect(r.headers, isEmpty);
    });

    test('method defaults: GET, POST with data, HEAD', () {
      expect(parseCurl('curl https://a.test').request!.method, 'GET');
      expect(parseCurl('curl https://a.test -d x=1').request!.method, 'POST');
      expect(parseCurl('curl -I https://a.test').request!.method, 'HEAD');
    });

    test('form data becomes urlencoded fields', () {
      final r = parseCurl("curl https://a.test -d 'a=1&b=x%20y'").request!;
      expect(r.bodyType, BodyType.formUrlEncoded);
      expect(r.formFields.map((e) => '${e.key}=${e.value}').toList(), <String>[
        'a=1',
        'b=x y',
      ]);
    });

    test('multipart -F with file', () {
      final r = parseCurl(
        "curl https://a.test -F 'name=x' -F 'file=@/tmp/a.png'",
      ).request!;
      expect(r.bodyType, BodyType.multipart);
      expect(r.formFields.length, 2);
      expect(r.formFields[1].isFile, isTrue);
      expect(r.formFields[1].value, '/tmp/a.png');
    });

    test('basic auth via -u', () {
      final r = parseCurl('curl -u user:pa:ss https://a.test').request!;
      expect(r.auth.type, AuthType.basic);
      expect(r.auth.username, 'user');
      expect(r.auth.password, 'pa:ss');
    });

    test('-G moves data into the query', () {
      final r = parseCurl('curl -G https://a.test -d q=1').request!;
      expect(r.method, 'GET');
      expect(r.bodyType, BodyType.none);
      expect(r.params.single.key, 'q');
    });

    test('--insecure is not honoured and is reported', () {
      final res = parseCurl('curl -k https://a.test');
      expect(
        res.notes.any(
          (n) => n.level == NoteLevel.warning && n.message.contains('insecure'),
        ),
        isTrue,
      );
    });

    test('unsupported options produce warnings, not failures', () {
      final res = parseCurl('curl --weird-flag https://a.test');
      expect(res.request, isNotNull);
      expect(res.notes.any((n) => n.message.contains('--weird-flag')), isTrue);
    });

    test('errors', () {
      expect(parseCurl('wget x').request, isNull);
      expect(parseCurl("curl 'x").request, isNull);
      expect(parseCurl('curl -X POST').request, isNull);
      expect(parseCurl('x' * 300000).request, isNull);
    });
  });

  group('exportCurl', () {
    const req = RequestModel(
      id: 'x',
      method: 'POST',
      url: 'https://api.test/items',
      params: <KeyValue>[KeyValue(key: 'q', value: 'a b')],
      headers: <KeyValue>[KeyValue(key: 'X-A', value: "it's")],
      bodyType: BodyType.json,
      body: '{"a":"it\'s"}',
      auth: AuthConfig(type: AuthType.bearer, token: 'TOPSECRET'),
    );

    test('omits secrets by default', () {
      final s = exportCurl(req);
      expect(s.contains('TOPSECRET'), isFalse);
      expect(s, contains('<token>'));
      expect(s, contains("-X 'POST'"));
      expect(s, contains('q=a+b'));
    });

    test('includes secrets only on request', () {
      expect(
        exportCurl(req, includeSecrets: true),
        contains('Bearer TOPSECRET'),
      );
    });

    test('quotes single quotes safely and round-trips', () {
      final s = exportCurl(req, includeSecrets: true);
      final back = parseCurl(s).request!;
      expect(back.method, 'POST');
      expect(back.url, 'https://api.test/items');
      expect(back.body, '{"a":"it\'s"}');
      expect(back.auth.token, 'TOPSECRET');
      expect(back.headers.single.value, "it's");
    });
  });
}
