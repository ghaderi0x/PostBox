import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/collections/domain/node_settings.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/http/application/request_executor.dart';
import 'package:postbox/features/http/data/io_http_engine.dart';
import 'package:postbox/features/http/domain/cookie_jar.dart';
import 'package:postbox/features/http/domain/request_builder.dart';
import 'package:postbox/features/requests/domain/request_models.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';

/// Echo server: answers with the request line, selected headers and the body.
Future<HttpServer> _echo() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    try {
      final body = await utf8.decoder.bind(req).join();
      req.response.headers.contentType = ContentType.json;
      req.response.headers.add('set-cookie', 'srv=1; Path=/');
      req.response.write(
        jsonEncode(<String, Object?>{
          'method': req.method,
          'path': req.uri.toString(),
          'auth': req.headers.value('authorization'),
          'team': req.headers.value('x-team'),
          'stamp': req.headers.value('x-stamp'),
          'cookie': req.headers.value('cookie'),
          'ctype': req.headers.value('content-type'),
          'body': body,
        }),
      );
      await req.response.close();
    } on Object {
      // Client went away.
    }
  });
  return server;
}

void main() {
  final servers = <HttpServer>[];
  final temp = <File>[];
  late HttpServer server;
  late String base;
  final settings = AppSettings();

  setUp(() async {
    server = await _echo();
    servers.add(server);
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    for (final s in servers) {
      await s.close(force: true);
    }
    servers.clear();
    for (final f in temp) {
      if (f.existsSync()) f.deleteSync();
    }
    temp.clear();
  });

  RequestExecutor newExecutor({CookieJar? jar}) =>
      RequestExecutor(engine: const IoHttpEngine(), cookieJar: jar);
  Map<String, dynamic> echoed(ExecutionOutcome o) =>
      jsonDecode(utf8.decode(o.result!.body)) as Map<String, dynamic>;

  test(
    'inherited auth and headers reach the server; the request keeps its own header',
    () async {
      final ctx = InheritanceResolver.resolve(<SettingsLevel>[
        SettingsLevel(
          'Col',
          NodeSettings(
            auth: const AuthConfig(type: AuthType.bearer, token: 'col-token'),
            headers: const <KeyValue>[
              KeyValue(key: 'X-Team', value: 'collection'),
              KeyValue(key: 'X-Stamp', value: 'inherited'),
            ],
          ),
        ),
      ]);
      final o = await newExecutor().execute(
        RequestModel(
          id: 'r',
          url: '$base/x',
          auth: const AuthConfig(type: AuthType.inherit),
          headers: const <KeyValue>[KeyValue(key: 'x-stamp', value: 'own')],
        ),
        vars: VariableResolver(),
        settings: settings,
        inherited: ctx,
      );
      expect(o.ok, isTrue);
      expect(echoed(o)['auth'], 'Bearer col-token');
      expect(echoed(o)['team'], 'collection');
      expect(echoed(o)['stamp'], 'own');
      expect(o.effectiveAuthSource, 'Col');
    },
  );

  test('a request with its own auth ignores the inherited one', () async {
    final ctx = InheritanceResolver.resolve(<SettingsLevel>[
      SettingsLevel(
        'Col',
        NodeSettings(
          auth: const AuthConfig(type: AuthType.bearer, token: 'col-token'),
        ),
      ),
    ]);
    final o = await newExecutor().execute(
      RequestModel(
        id: 'r',
        url: '$base/x',
        auth: const AuthConfig(type: AuthType.bearer, token: 'mine'),
      ),
      vars: VariableResolver(),
      settings: settings,
      inherited: ctx,
    );
    expect(echoed(o)['auth'], 'Bearer mine');
    expect(o.effectiveAuthSource, isNull);
  });

  test(
    'folder and request variables resolve with the documented precedence',
    () async {
      final o = await newExecutor().execute(
        RequestModel(
          id: 'r',
          url: '$base/{{seg}}/{{who}}',
          variables: const <KeyValue>[KeyValue(key: 'who', value: 'request')],
        ),
        vars: VariableResolver(
          collection: <Variable>[
            Variable(id: 'c', key: 'seg', value: 'collection'),
          ],
        ),
        settings: settings,
        inherited: EffectiveContext(
          folderVariables: <Variable>[
            Variable(id: 'f', key: 'seg', value: 'folder'),
            Variable(id: 'f2', key: 'who', value: 'folder'),
          ],
        ),
      );
      expect(echoed(o)['path'], '/folder/request');
    },
  );

  test('a pre-request script changes the outgoing request', () async {
    final o = await newExecutor().execute(
      RequestModel(
        id: 'r',
        url: '$base/x',
        preScript:
            'request.headers.set("X-Stamp", "from-script"); request.url = request.url + "?s=" + vars.get("seed");',
        variables: const <KeyValue>[KeyValue(key: 'seed', value: '7')],
      ),
      vars: VariableResolver(),
      settings: settings,
    );
    expect(echoed(o)['stamp'], 'from-script');
    expect(echoed(o)['path'], '/x?s=7');
  });

  test('collection, folder and request pre-scripts run in order', () async {
    final o = await newExecutor().execute(
      RequestModel(
        id: 'r',
        url: '$base/x',
        preScript:
            'vars.set("order", vars.get("order") + "R"); request.headers.set("X-Stamp", vars.get("order"));',
      ),
      vars: VariableResolver(),
      settings: settings,
      inherited: const EffectiveContext(
        preScripts: <String>[
          'vars.set("order", "C");',
          'vars.set("order", vars.get("order") + "F");',
        ],
      ),
    );
    expect(echoed(o)['stamp'], 'CFR');
  });

  test(
    'a failing pre-request script stops the request: nothing is sent',
    () async {
      var hits = 0;
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(s);
      s.listen((r) {
        hits++;
        r.response.close();
      });
      final o = await newExecutor().execute(
        RequestModel(
          id: 'r',
          url: 'http://127.0.0.1:${s.port}/',
          preScript: 'fail("nope");',
        ),
        vars: VariableResolver(),
        settings: settings,
      );
      expect(o.ok, isFalse);
      expect(o.scriptError, contains('nope'));
      expect(o.failure, isNull);
      expect(hits, 0);
    },
  );

  test('post-response scripts: tests, logs, variables and errors', () async {
    final o = await newExecutor().execute(
      RequestModel(
        id: 'r',
        method: 'POST',
        url: '$base/x',
        bodyType: BodyType.json,
        body: '{"k":1}',
        postScript: '''
          let echo = response.json();
          test("status 200", response.status == 200);
          test("method echoed", echo.method == "POST");
          log("path", echo.path);
          vars.set("got", echo.method);
        ''',
      ),
      vars: VariableResolver(),
      settings: settings,
      inherited: const EffectiveContext(
        postScripts: <String>['test("folder post ran", true);'],
      ),
    );
    expect(o.scriptError, isNull);
    expect(o.scriptTests.map((t) => t.name), <String>[
      'status 200',
      'method echoed',
      'folder post ran',
    ]);
    expect(o.assertionsPassed, isTrue);
    expect(o.scriptLogs.single, 'path /x');
    expect(o.extracted['got'], 'POST');

    final bad = await newExecutor().execute(
      RequestModel(
        id: 'r',
        url: '$base/x',
        postScript: 'test("a", false); oops();',
      ),
      vars: VariableResolver(),
      settings: settings,
    );
    expect(bad.ok, isTrue); // the response is still shown
    expect(bad.scriptError, contains('oops'));
    expect(bad.assertionsPassed, isFalse);
  });

  test('scripts cannot see secret variables', () async {
    final o = await newExecutor().execute(
      RequestModel(
        id: 'r',
        url: '$base/x',
        preScript: 'request.headers.set("X-Stamp", str(vars.get("tok")));',
      ),
      vars: VariableResolver(
        environment: <Variable>[
          Variable(id: 't', key: 'tok', value: 'TOP', secret: true),
        ],
      ),
      settings: settings,
    );
    expect(echoed(o)['stamp'], 'null');
  });

  test(
    'cookie jar is used when the setting is on and ignored when off',
    () async {
      final jar = CookieJarImpl();
      final executor = newExecutor(jar: jar);
      await executor.execute(
        RequestModel(id: 'r', url: '$base/a'),
        vars: VariableResolver(),
        settings: settings,
      );
      final second = await executor.execute(
        RequestModel(id: 'r', url: '$base/b'),
        vars: VariableResolver(),
        settings: settings,
      );
      expect(echoed(second)['cookie'], 'srv=1');

      final off = await executor.execute(
        RequestModel(id: 'r', url: '$base/c'),
        vars: VariableResolver(),
        settings: settings.copyWith(useCookieJar: false),
      );
      expect(echoed(off)['cookie'], isNull);
    },
  );

  test('binary body sends the file bytes with a default content type', () async {
    final f = File(
      '${Directory.systemTemp.path}/postbox_bin_${DateTime.now().microsecondsSinceEpoch}.dat',
    )..writeAsBytesSync(Uint8List.fromList(<int>[104, 105, 33])); // "hi!"
    temp.add(f);
    final o = await newExecutor().execute(
      RequestModel(
        id: 'r',
        method: 'POST',
        url: '$base/up',
        bodyType: BodyType.binary,
        body: f.path,
      ),
      vars: VariableResolver(),
      settings: settings,
    );
    expect(echoed(o)['body'], 'hi!');
    expect(echoed(o)['ctype'], 'application/octet-stream');
    expect(o.request!.preview.bodyPreview, contains('binary file'));
  });

  test('binary body: missing file and oversize file are build errors', () async {
    final missing = await newExecutor().execute(
      RequestModel(
        id: 'r',
        method: 'POST',
        url: '$base/up',
        bodyType: BodyType.binary,
        body: '/no/such/file',
      ),
      vars: VariableResolver(),
      settings: settings,
    );
    expect(missing.buildError?.code, 'file_missing');

    final empty = await newExecutor().execute(
      RequestModel(
        id: 'r',
        method: 'POST',
        url: '$base/up',
        bodyType: BodyType.binary,
        body: '',
      ),
      vars: VariableResolver(),
      settings: settings,
    );
    expect(empty.buildError?.code, 'file_missing');

    final big = File(
      '${Directory.systemTemp.path}/postbox_big_${DateTime.now().microsecondsSinceEpoch}.dat',
    )..writeAsBytesSync(Uint8List(2 * 1024 * 1024));
    temp.add(big);
    final tooBig = await newExecutor().execute(
      RequestModel(
        id: 'r',
        method: 'POST',
        url: '$base/up',
        bodyType: BodyType.binary,
        body: big.path,
      ),
      vars: VariableResolver(),
      settings: settings.copyWith(maxRequestMb: 1),
    );
    expect(tooBig.buildError?.code, 'request_too_large');
  });

  test(
    'HTTP version and certificate settings reach the request spec',
    () async {
      final built = await const RequestBuilder().build(
        RequestModel(id: 'r', url: '$base/x'),
        VariableResolver(),
        settings.copyWith(
          httpVersion: HttpVersionPref.auto,
          clientCertPath: '/c.pem',
          clientKeyPath: '/k.pem',
          caCertPath: '/ca.pem',
        ),
        clientKeyPassword: 'pw',
      );
      expect(built.spec.preferHttp2, isTrue);
      expect(built.spec.clientCertPath, '/c.pem');
      expect(built.spec.clientKeyPath, '/k.pem');
      expect(built.spec.clientKeyPassword, 'pw');
      expect(built.spec.caCertPath, '/ca.pem');
      final plain = await const RequestBuilder().build(
        RequestModel(id: 'r', url: '$base/x'),
        VariableResolver(),
        settings,
      );
      expect(plain.spec.preferHttp2, isFalse);
      expect(plain.spec.clientCertPath, isNull);
      expect(plain.spec.usesCustomTls, isFalse);
    },
  );
}
