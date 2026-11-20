import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/runner/domain/run_data.dart';
import 'package:postbox/features/shortcuts/shortcut_catalog.dart';

void main() {
  group('run data', () {
    test('parses CSV with quotes, escaped quotes and CRLF', () {
      final d = parseRunData('name,note\r\n"Ann, B","say ""hi"""\r\nBob,\r\n');
      expect(d.columns, <String>['name', 'note']);
      expect(d.rows, <Map<String, String>>[
        <String, String>{'name': 'Ann, B', 'note': 'say "hi"'},
        <String, String>{'name': 'Bob', 'note': ''},
      ]);
    });

    test('detects semicolon and tab delimiters', () {
      expect(parseRunData('a;b\n1;2').rows.single, <String, String>{
        'a': '1',
        'b': '2',
      });
      expect(parseRunData('a\tb\n1\t2').rows.single, <String, String>{
        'a': '1',
        'b': '2',
      });
    });

    test('newlines inside quoted cells are kept', () {
      expect(parseRunData('a,b\n"x\ny",2').rows.single['a'], 'x\ny');
    });

    test('short rows are padded with empty strings', () {
      expect(parseRunData('a,b,c\n1').rows.single, <String, String>{
        'a': '1',
        'b': '',
        'c': '',
      });
    });

    test('parses a JSON array of objects and stringifies values', () {
      final d = parseRunData(
        '[{"id": 1, "ok": true, "tags": ["x"]}, {"id": 2}]',
      );
      expect(d.columns, <String>['id', 'ok', 'tags']);
      expect(d.rows.first, <String, String>{
        'id': '1',
        'ok': 'true',
        'tags': '["x"]',
      });
      expect(d.rows.last, <String, String>{'id': '2'});
    });

    test('rejects bad input with stable codes', () {
      RunDataException? e(String t) {
        try {
          parseRunData(t);
        } on RunDataException catch (x) {
          return x;
        }
        return null;
      }

      expect(e('   ')!.code, 'empty');
      expect(e('a,b')!.code, 'empty'); // header only
      expect(e('[1,2]')!.code, 'bad_json');
      expect(e('[{"a":')!.code, 'bad_json');
      expect(e('a,b\n"open')!.code, 'bad_csv');
      expect(e('x' * (kMaxRunDataBytes + 1))!.code, 'too_large');
      final many =
          'a\n${List<String>.filled(kMaxRunDataRows + 5, '1').join('\n')}';
      expect(e(many)!.code, 'too_many_rows');
    });
  });

  group('shortcuts', () {
    test('parse and serialize round trip', () {
      final c = KeyCombo.parse('Ctrl+Shift+K')!;
      expect(c.serialize(), 'ctrl+shift+k');
      expect(c.display(), 'Ctrl+Shift+K');
      expect(KeyCombo.parse(c.serialize()), c);
    });

    test('plain typing keys are not valid shortcuts', () {
      expect(KeyCombo.parse('k'), isNull);
      expect(KeyCombo.parse('shift+k'), isNull);
      expect(KeyCombo.parse('f5'), isNotNull);
      expect(KeyCombo.parse('ctrl+nonsense'), isNull);
      expect(KeyCombo.parse('ctrl+a+b'), isNull);
      expect(KeyCombo.parse(''), isNull);
    });

    test('defaults are valid and unique', () {
      expect(kDefaultShortcuts.length, ShortcutAction.values.length);
      expect(kDefaultShortcuts.values.every((c) => c.isValid), isTrue);
      expect(
        kDefaultShortcuts.values.toSet().length,
        ShortcutAction.values.length,
      );
    });

    test('overrides apply; invalid ones are ignored', () {
      final m = effectiveShortcuts(<String, String>{
        'send': 'ctrl+shift+enter',
        'save': 'oops',
        'bogus': 'ctrl+x',
      });
      expect(m[ShortcutAction.send]!.serialize(), 'ctrl+shift+enter');
      expect(m[ShortcutAction.save], kDefaultShortcuts[ShortcutAction.save]);
    });

    test('a duplicate binding falls back to the default', () {
      final m = effectiveShortcuts(<String, String>{'save': 'ctrl+k'});
      expect(m[ShortcutAction.save], kDefaultShortcuts[ShortcutAction.save]);
      expect(m[ShortcutAction.commandPalette]!.serialize(), 'ctrl+k');
    });

    test('conflict detection ignores the action being edited', () {
      final m = effectiveShortcuts(const <String, String>{});
      final k = KeyCombo.parse('ctrl+k')!;
      expect(
        findShortcutConflict(m, k, except: ShortcutAction.save),
        ShortcutAction.commandPalette,
      );
      expect(
        findShortcutConflict(m, k, except: ShortcutAction.commandPalette),
        isNull,
      );
    });
  });
}
