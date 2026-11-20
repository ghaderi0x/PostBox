import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/environments/domain/variables.dart';
import 'package:postbox/features/http/domain/http_engine.dart';
import 'package:postbox/features/requests/domain/request_models.dart';
import 'package:postbox/features/scripting/script_host.dart';
import 'package:postbox/features/scripting/script_interpreter.dart';
import 'package:postbox/features/scripting/script_parser.dart';

HttpResult _response(String body, {int status = 200}) => HttpResult(
  statusCode: status,
  reasonPhrase: 'OK',
  headers: const <String, List<String>>{
    'content-type': <String>['application/json'],
  },
  body: Uint8List.fromList(utf8.encode(body)),
  truncated: false,
  duration: const Duration(milliseconds: 42),
  finalUrl: Uri.parse('https://example.test/x'),
  redirects: const <Uri>[],
);

void main() {
  const runner = ScriptRunner();
  final vars = VariableResolver(
    environment: <Variable>[
      Variable(id: 'a', key: 'host', value: 'example.test'),
      Variable(id: 'b', key: 'apiKey', value: 'TOP-SECRET', secret: true),
    ],
  );

  group('interpreter', () {
    Object? eval(String expr) {
      final out = <String>[];
      final i = ScriptInterpreter(
        globals: <String, Object?>{},
        functions: <String, ScriptFunction>{
          'emit': (a) {
            out.add(ScriptInterpreter.display(a.first));
            return null;
          },
        },
      );
      i.run(parseScript('emit($expr);'));
      return out.single;
    }

    test('arithmetic, strings and comparison', () {
      expect(eval('1 + 2 * 3'), '7');
      expect(eval('"a" + 1'), 'a1');
      expect(eval('10 / 4'), '2.5');
      expect(eval('10 / 5'), '2');
      expect(eval('7 % 4'), '3');
      expect(eval('"abc" < "abd"'), 'true');
      expect(eval('null ?? "x"'), 'x');
      expect(eval('!0'), 'true');
    });

    test('lists, objects, methods and indexing', () {
      expect(eval('[1,2,3].length'), '3');
      expect(eval('{"a": {"b": 5}}.a.b'), '5');
      expect(eval('"a,b,c".split(",")[1]'), 'b');
      expect(eval('"Hello".toUpperCase()'), 'HELLO');
      expect(eval('["x","y"].join("-")'), 'x-y');
    });

    test('if, else if, for and assignment', () {
      final out = <String>[];
      final i = ScriptInterpreter(
        globals: <String, Object?>{},
        functions: <String, ScriptFunction>{
          'emit': (a) {
            out.add(ScriptInterpreter.display(a.first));
            return null;
          },
        },
      );
      i.run(
        parseScript('''
        let total = 0;
        for n in [1, 2, 3] { total = total + n; }
        if (total > 10) { emit("big"); } else if (total == 6) { emit("six"); } else { emit("other"); }
      '''),
      );
      expect(out, <String>['six']);
    });

    test('unknown names and functions are errors with a line number', () {
      expect(
        () => ScriptInterpreter(
          globals: <String, Object?>{},
          functions: <String, ScriptFunction>{},
        ).run(parseScript('let a = 1;\nlet b = missing;')),
        throwsA(isA<ScriptException>().having((e) => e.line, 'line', 2)),
      );
      expect(
        () => ScriptInterpreter(
          globals: <String, Object?>{},
          functions: <String, ScriptFunction>{},
        ).run(parseScript('open("file");')),
        throwsA(isA<ScriptException>()),
      );
    });

    test('step limit stops runaway loops', () {
      final big = List<int>.generate(9000, (i) => i).join(',');
      final i = ScriptInterpreter(
        globals: <String, Object?>{},
        functions: <String, ScriptFunction>{},
        limits: const ScriptLimits(maxSteps: 2000),
      );
      expect(
        () => i.run(
          parseScript(
            'for a in [$big] { for b in [1,2,3] { let c = a + b; } }',
          ),
        ),
        throwsA(
          isA<ScriptException>().having(
            (e) => e.message,
            'message',
            contains('too many steps'),
          ),
        ),
      );
    });

    test('string growth is limited', () {
      final i = ScriptInterpreter(
        globals: <String, Object?>{},
        functions: <String, ScriptFunction>{},
        limits: const ScriptLimits(maxStringLength: 1000),
      );
      expect(
        () => i.run(
          parseScript(
            'let s = "x"; for n in [1,2,3,4,5,6,7,8,9,10,11,12] { s = s + s; }',
          ),
        ),
        throwsA(isA<ScriptException>()),
      );
    });

    test('parser rejects deep nesting and long scripts', () {
      expect(() => parseScript('(' * 500), throwsA(isA<ScriptException>()));
      expect(
        () => parseScript('x' * (kMaxScriptChars + 1)),
        throwsA(isA<ScriptException>()),
      );
    });
  });

  group('pre-request scripts', () {
    final base = RequestModel(
      id: 'r',
      method: 'GET',
      url: 'https://{{host}}/items',
      headers: const <KeyValue>[KeyValue(key: 'Accept', value: 'text/plain')],
    );

    test('can change url, method, headers and set variables', () {
      final (req, res) = runner.runPre(
        scripts: <String>[
          '''
          request.headers.set("X-Id", "42");
          request.headers["Accept"] = "application/json";
          request.method = "post";
          request.url = request.url + "?a=1";
          vars.set("stamp", "s1");
          log("done", 1);
          ''',
        ],
        request: base,
        vars: vars,
      );
      expect(res.error, isNull);
      expect(req.method, 'POST');
      expect(req.url, 'https://{{host}}/items?a=1');
      expect(
        req.headers.firstWhere((h) => h.key == 'Accept').value,
        'application/json',
      );
      expect(
        req.headers.any((h) => h.key == 'X-Id' && h.value == '42'),
        isTrue,
      );
      expect(res.variableWrites['stamp'], 's1');
      expect(res.logs.single, 'done 1');
    });

    test('secret variables are invisible', () {
      final (_, res) = runner.runPre(
        scripts: <String>[
          'vars.set("seen", str(vars.get("apiKey")));\nvars.set("host2", vars.get("host"));',
        ],
        request: base,
        vars: vars,
      );
      expect(res.variableWrites['seen'], 'null');
      expect(res.variableWrites['host2'], 'example.test');
    });

    test('later scripts see earlier writes; an error stops the chain', () {
      final (_, res) = runner.runPre(
        scripts: <String>[
          'vars.set("a", "1");',
          'vars.set("b", vars.get("a") + "2");',
          'fail("stop here");',
          'vars.set("never", "x");',
        ],
        request: base,
        vars: vars,
      );
      expect(res.variableWrites['b'], '12');
      expect(res.variableWrites.containsKey('never'), isFalse);
      expect(res.error, contains('stop here'));
    });

    test('request.body cannot be set on a form body', () {
      final form = base.copyWith(bodyType: BodyType.formUrlEncoded);
      final (_, res) = runner.runPre(
        scripts: <String>['request.body = "x";'],
        request: form,
        vars: vars,
      );
      expect(res.error, isNotNull);
    });

    test('no scripts means the request is returned unchanged', () {
      final (req, res) = runner.runPre(
        scripts: <String>['', '  '],
        request: base,
        vars: vars,
      );
      expect(identical(req, base), isTrue);
      expect(res.hasContent, isFalse);
    });
  });

  group('post-response scripts', () {
    final req = RequestModel(id: 'r', url: 'https://example.test/x');

    test('read the response and report tests', () {
      final res = runner.runPost(
        scripts: <String>[
          '''
          let data = response.json();
          test("status ok", response.status == 200);
          test("has id", data.id == 7);
          test("fast", response.time < 10);
          vars.set("id", str(data.id));
          ''',
        ],
        request: req,
        vars: vars,
        response: _response('{"id": 7}'),
      );
      expect(res.error, isNull);
      expect(res.tests.map((t) => (t.name, t.passed)), <(String, bool)>[
        ('status ok', true),
        ('has id', true),
        ('fast', false),
      ]);
      expect(res.variableWrites['id'], '7');
    });

    test('invalid JSON is a script error, not a crash', () {
      final res = runner.runPost(
        scripts: <String>['response.json();'],
        request: req,
        vars: vars,
        response: _response('not json'),
      );
      expect(res.error, contains('not valid JSON'));
    });

    test('response headers are read-only', () {
      final res = runner.runPost(
        scripts: <String>['response.headers.set("a", "b");'],
        request: req,
        vars: vars,
        response: _response('{}'),
      );
      expect(res.error, contains('read-only'));
    });

    test('helpers: base64, sha256 and urlencode', () {
      final res = runner.runPost(
        scripts: <String>[
          'vars.set("b", base64("hi")); vars.set("d", base64decode(base64("hi"))); vars.set("u", urlencode("a b&c"));',
        ],
        request: req,
        vars: vars,
        response: _response('{}'),
      );
      expect(res.variableWrites['b'], 'aGk=');
      expect(res.variableWrites['d'], 'hi');
      expect(res.variableWrites['u'], 'a+b%26c');
    });
  });
}
