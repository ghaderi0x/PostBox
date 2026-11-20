import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/http/domain/cookie_jar.dart';

void main() {
  var now = DateTime.utc(2026, 1, 1, 12);
  CookieJarImpl newJar([CookiePersistence? p]) =>
      CookieJarImpl(persistence: p, clock: () => now);
  final url = Uri.parse('https://api.example.test/v1/users');

  setUp(() => now = DateTime.utc(2026, 1, 1, 12));

  group('Set-Cookie parsing', () {
    test('stores a host-only session cookie and sends it back', () {
      final jar = newJar()
        ..storeFromResponse(url, <String>['sid=abc123; Path=/; HttpOnly']);
      expect(
        jar.cookieHeader(Uri.parse('https://api.example.test/anything')),
        'sid=abc123',
      );
      expect(
        jar.cookieHeader(Uri.parse('https://other.example.test/')),
        isNull,
      );
      final c = jar.all().single;
      expect(c.hostOnly, isTrue);
      expect(c.httpOnly, isTrue);
      expect(c.expires, isNull);
    });

    test('Domain attribute shares the cookie with subdomains', () {
      final jar = newJar()
        ..storeFromResponse(url, <String>['t=1; Domain=example.test; Path=/']);
      expect(jar.cookieHeader(Uri.parse('https://www.example.test/')), 't=1');
      expect(jar.cookieHeader(Uri.parse('https://example.test/')), 't=1');
      expect(jar.cookieHeader(Uri.parse('https://evilexample.test/')), isNull);
    });

    test('rejects a Domain that does not match the response host', () {
      final jar = newJar()
        ..storeFromResponse(url, <String>['x=1; Domain=attacker.test']);
      expect(jar.all(), isEmpty);
    });

    test('rejects a bare top-level domain', () {
      final jar = newJar()
        ..storeFromResponse(url, <String>['x=1; Domain=test']);
      expect(jar.all(), isEmpty);
    });

    test('Secure cookies are only set and sent over https', () {
      final jar = newJar();
      jar.storeFromResponse(Uri.parse('http://api.example.test/'), <String>[
        's=1; Secure',
      ]);
      expect(jar.all(), isEmpty);
      jar.storeFromResponse(url, <String>['s=1; Secure; Path=/']);
      expect(jar.cookieHeader(Uri.parse('https://api.example.test/')), 's=1');
      expect(jar.cookieHeader(Uri.parse('http://api.example.test/')), isNull);
    });

    test('localhost may use Secure cookies over http', () {
      final jar = newJar()
        ..storeFromResponse(Uri.parse('http://localhost:3000/'), <String>[
          's=1; Secure; Path=/',
        ]);
      expect(jar.cookieHeader(Uri.parse('http://localhost:3000/')), 's=1');
    });

    test('__Host- and __Secure- prefixes are enforced', () {
      final jar = newJar();
      jar.storeFromResponse(url, <String>[
        '__Host-a=1; Path=/',
        '__Host-b=1; Secure; Path=/x',
        '__Secure-c=1',
        '__Host-ok=1; Secure; Path=/',
        '__Secure-ok=1; Secure',
      ]);
      expect(jar.all().map((c) => c.name).toSet(), <String>{
        '__Host-ok',
        '__Secure-ok',
      });
    });

    test(
      'Max-Age and Expires set the lifetime; expired cookies are dropped',
      () {
        final jar = newJar()
          ..storeFromResponse(url, <String>[
            'a=1; Max-Age=60',
            'b=2; Expires=Thu, 01 Jan 2026 12:30:00 GMT',
          ]);
        expect(jar.cookieHeader(url), contains('a=1'));
        expect(jar.cookieHeader(url), contains('b=2'));
        now = now.add(const Duration(minutes: 5));
        expect(jar.cookieHeader(url), 'b=2');
        now = now.add(const Duration(hours: 1));
        expect(jar.cookieHeader(url), isNull);
        expect(jar.all(), isEmpty);
      },
    );

    test('Max-Age=0 deletes an existing cookie', () {
      final jar = newJar()..storeFromResponse(url, <String>['a=1; Path=/']);
      jar.storeFromResponse(url, <String>['a=; Max-Age=0; Path=/']);
      expect(jar.all(), isEmpty);
    });

    test('a later cookie with the same name replaces the earlier one', () {
      final jar = newJar()..storeFromResponse(url, <String>['a=1; Path=/']);
      jar.storeFromResponse(url, <String>['a=2; Path=/']);
      expect(jar.all().single.value, '2');
    });

    test('malformed and oversized cookies are ignored', () {
      final jar = newJar()
        ..storeFromResponse(url, <String>[
          'novalue',
          '=x',
          'big=${'x' * 5000}',
          'ok=1',
        ]);
      expect(jar.all().single.name, 'ok');
    });
  });

  group('matching', () {
    test('path matching follows RFC 6265', () {
      final jar = newJar()..storeFromResponse(url, <String>['p=1; Path=/api']);
      expect(
        jar.cookieHeader(Uri.parse('https://api.example.test/api')),
        'p=1',
      );
      expect(
        jar.cookieHeader(Uri.parse('https://api.example.test/api/users')),
        'p=1',
      );
      expect(
        jar.cookieHeader(Uri.parse('https://api.example.test/apix')),
        isNull,
      );
      expect(jar.cookieHeader(Uri.parse('https://api.example.test/')), isNull);
    });

    test('default path is the directory of the request path', () {
      final jar = newJar()
        ..storeFromResponse(Uri.parse('https://h.test/a/b/c'), <String>['d=1']);
      expect(jar.all().single.path, '/a/b');
    });

    test('longer paths come first', () {
      final jar = newJar()
        ..storeFromResponse(url, <String>['a=1; Path=/', 'b=2; Path=/v1']);
      expect(
        jar.cookieHeader(Uri.parse('https://api.example.test/v1/x')),
        'b=2; a=1',
      );
    });

    test('IP hosts never match by suffix', () {
      final jar = newJar()
        ..storeFromResponse(Uri.parse('http://10.0.0.5/'), <String>[
          'a=1; Domain=0.0.5',
        ]);
      expect(jar.all(), isEmpty);
    });
  });

  group('limits and persistence', () {
    test('per-domain limit evicts the oldest cookies', () {
      final jar = newJar();
      for (var i = 0; i < CookieJarImpl.maxPerDomain + 20; i++) {
        now = now.add(const Duration(seconds: 1));
        jar.storeFromResponse(url, <String>['c$i=1; Path=/']);
      }
      final all = jar.all();
      expect(all.length, CookieJarImpl.maxPerDomain);
      expect(all.any((c) => c.name == 'c0'), isFalse);
      expect(
        all.any((c) => c.name == 'c${CookieJarImpl.maxPerDomain + 19}'),
        isTrue,
      );
    });

    test('changes are written through and reloaded', () {
      final store = _MemoryPersistence();
      final jar = newJar(store)
        ..storeFromResponse(url, <String>[
          'a=1; Path=/; Max-Age=3600',
          'b=2; Path=/',
        ]);
      expect(store.rows.length, 2);
      jar.delete(jar.all().first);
      expect(store.rows.length, 1);
      final reloaded = newJar(store);
      expect(reloaded.all().length, 1);
      reloaded.clear();
      expect(store.rows, isEmpty);
    });

    test('expired cookies are removed from storage on load', () {
      final store = _MemoryPersistence();
      newJar(store).storeFromResponse(url, <String>['a=1; Path=/; Max-Age=10']);
      now = now.add(const Duration(hours: 1));
      expect(newJar(store).all(), isEmpty);
      expect(store.rows, isEmpty);
    });
  });
}

class _MemoryPersistence implements CookiePersistence {
  final Map<String, StoredCookie> rows = <String, StoredCookie>{};

  @override
  List<StoredCookie> load() => rows.values.toList();
  @override
  void upsert(StoredCookie c) => rows[c.key] = c;
  @override
  void remove(StoredCookie c) => rows.remove(c.key);
  @override
  void clear() => rows.clear();
}
