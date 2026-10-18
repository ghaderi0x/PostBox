import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/testing/domain/assertions.dart';
import 'package:postbox/features/testing/domain/json_path.dart';

import '../helpers/fixtures.dart';

void main() {
  group('JsonPath', () {
    final doc = <String, dynamic>{
      'data': <String, dynamic>{
        'id': 7,
        'items': <dynamic>[
          <String, dynamic>{'name': 'a'},
          <String, dynamic>{'name': 'b'},
        ],
        'odd key': true,
      },
    };

    test('dot and index access', () {
      expect(JsonPath.parse(r'$.data.id')!.evaluate(doc), (true, 7));
      expect(JsonPath.parse(r'$.data.items[1].name')!.evaluate(doc), (true, 'b'));
    });

    test('bracket string keys', () {
      expect(JsonPath.parse(r"$.data['odd key']")!.evaluate(doc), (true, true));
    });

    test('missing path', () {
      expect(JsonPath.parse(r'$.data.nope')!.evaluate(doc).$1, isFalse);
      expect(JsonPath.parse(r'$.data.items[9]')!.evaluate(doc).$1, isFalse);
    });

    test('rejects unsupported syntax', () {
      expect(JsonPath.parse('data.id'), isNull);
      expect(JsonPath.parse(r'$..id'), isNull);
      expect(JsonPath.parse(r'$.items[*]'), isNull);
      expect(JsonPath.parse(r'$.a['), isNull);
    });
  });

  group('assertions', () {
    final res = fakeResult(
      status: 201,
      reason: 'Created',
      headers: const <String, List<String>>{
        'Content-Type': <String>['application/json'],
      },
      body: '{"token":"abc","n":3}',
      duration: const Duration(milliseconds: 80),
    );

    Assertion a(AssertionKind k, {String target = '', String expected = ''}) =>
        Assertion(id: k.name, kind: k, target: target, expected: expected);

    test('status and duration', () {
      final r = evaluateAssertions(<Assertion>[
        a(AssertionKind.statusEquals, expected: '201'),
        a(AssertionKind.statusEquals, expected: '200'),
        a(AssertionKind.statusIsSuccess),
        a(AssertionKind.durationLessThanMs, expected: '100'),
        a(AssertionKind.durationLessThanMs, expected: '50'),
      ], res);
      expect(r.map((e) => e.passed).toList(), <bool>[true, false, true, true, false]);
    });

    test('headers are case-insensitive', () {
      final r = evaluateAssertions(<Assertion>[
        a(AssertionKind.headerEquals, target: 'content-type', expected: 'application/json'),
        a(AssertionKind.headerContains, target: 'CONTENT-TYPE', expected: 'json'),
        a(AssertionKind.headerEquals, target: 'x-missing', expected: 'x'),
      ], res);
      expect(r.map((e) => e.passed).toList(), <bool>[true, true, false]);
    });

    test('body and json path', () {
      final r = evaluateAssertions(<Assertion>[
        a(AssertionKind.bodyContains, expected: 'token'),
        a(AssertionKind.jsonPathEquals, target: r'$.token', expected: 'abc'),
        a(AssertionKind.jsonPathEquals, target: r'$.n', expected: '3'),
        a(AssertionKind.jsonPathExists, target: r'$.token'),
        a(AssertionKind.jsonPathExists, target: r'$.nope'),
        a(AssertionKind.jsonPathEquals, target: 'bad', expected: 'x'),
      ], res);
      expect(r.map((e) => e.passed).toList(), <bool>[true, true, true, true, false, false]);
    });

    test('json assertions fail cleanly on non-JSON bodies', () {
      final r = evaluateAssertions(
        <Assertion>[a(AssertionKind.jsonPathExists, target: r'$.a')],
        fakeResult(body: 'not json'),
      );
      expect(r.single.passed, isFalse);
    });
  });

  test('applyExtractions copies json values and headers', () {
    final res = fakeResult(
      headers: const <String, List<String>>{
        'X-Request-Id': <String>['r-1'],
      },
      body: '{"user":{"id":42},"name":"x"}',
    );
    final out = applyExtractions(<Extraction>[
      Extraction(id: '1', variable: 'uid', source: ExtractionSource.jsonPath, expression: r'$.user.id'),
      Extraction(id: '2', variable: 'rid', source: ExtractionSource.header, expression: 'x-request-id'),
      Extraction(id: '3', variable: 'missing', source: ExtractionSource.jsonPath, expression: r'$.zzz'),
      Extraction(id: '4', variable: '', source: ExtractionSource.jsonPath, expression: r'$.name'),
    ], res);
    expect(out, <String, String>{'uid': '42', 'rid': 'r-1'});
  });
}
