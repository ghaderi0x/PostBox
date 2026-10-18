import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/util/format.dart';
import 'package:postbox/core/util/ids.dart';
import 'package:postbox/core/util/jalali.dart';
import 'package:postbox/core/util/redact.dart';

void main() {
  group('Redactor', () {
    test('url masks query values and removes userinfo and fragment', () {
      expect(
        Redactor.url('https://user:pw@api.test/x?a=1&b=2#frag'),
        'https://api.test/x?a=••••&b=••••',
      );
    });

    test('url without query is unchanged', () {
      expect(Redactor.url('https://api.test/x'), 'https://api.test/x');
    });

    test('freeText scrubs query strings, bearer tokens and key=value secrets', () {
      final out = Redactor.freeText('GET https://x.test/a?token=abc Bearer abc.def password=hunter2');
      expect(out.contains('abc'), isFalse);
      expect(out.contains('hunter2'), isFalse);
      expect(out.contains('https://x.test/a?••••'), isTrue);
    });

    test('sensitive header detection', () {
      expect(Redactor.isSensitiveHeader('Authorization'), isTrue);
      expect(Redactor.isSensitiveHeader('X-Api-Key'), isTrue);
      expect(Redactor.isSensitiveHeader('Cookie'), isTrue);
      expect(Redactor.isSensitiveHeader('Accept'), isFalse);
      expect(Redactor.headerValue('Authorization', 'Bearer x'), Redactor.mask);
    });
  });

  group('Fmt', () {
    test('latin digits by default', () {
      expect(const Fmt().digits('200 OK'), '200 OK');
    });

    test('persian digits', () {
      expect(const Fmt(persianDigits: true).digits('Status 200'), 'Status ۲۰۰');
    });

    test('bytes and duration', () {
      const f = Fmt();
      expect(f.bytes(512), '512 B');
      expect(f.bytes(1536), '1.5 KB');
      expect(f.duration(const Duration(milliseconds: 250)), '250 ms');
      expect(f.duration(const Duration(milliseconds: 1500)), '1.50 s');
    });

    test('jalali date formatting', () {
      expect(const Fmt(jalali: true).dateTime(DateTime(2026, 10, 17, 9, 5)), '1405/07/25 09:05');
      expect(const Fmt().dateTime(DateTime(2026, 10, 17, 9, 5)), '2026/10/17 09:05');
    });
  });

  test('gregorianToJalali known dates', () {
    expect(gregorianToJalali(2026, 10, 17), <int>[1405, 7, 25]);
    expect(gregorianToJalali(2024, 1, 1), <int>[1402, 10, 11]);
    expect(gregorianToJalali(2026, 3, 21), <int>[1405, 1, 1]);
    expect(gregorianToJalali(2026, 3, 20), <int>[1404, 12, 29]);
  });

  test('newId is 32 hex chars and unique', () {
    final a = newId();
    final b = newId();
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a, isNot(b));
  });
}
