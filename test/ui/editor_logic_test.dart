import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/design/presets.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';
import 'package:postbox/ui/editor/editor_input_formatter.dart';
import 'package:postbox/ui/editor/find_logic.dart';
import 'package:postbox/ui/editor/highlighter.dart';
import 'package:postbox/ui/editor/json_tools.dart';

void main() {
  group('json tools', () {
    test('valid and empty input have no problem', () {
      expect(validateJson(''), isNull);
      expect(validateJson('   '), isNull);
      expect(validateJson('{"a": [1, 2, {"b": null}]}'), isNull);
    });

    test('variables do not make JSON invalid, even unquoted', () {
      expect(validateJson('{"id": {{id}}, "name": "{{name}}"}'), isNull);
    });

    test('errors carry a 1-based line and column', () {
      final p = validateJson('{\n  "a": ,\n}')!;
      expect(p.line, 2);
      expect(p.column, greaterThan(0));
      expect(p.offset, greaterThan(0));
      expect(validateJson('{"a": 1,}'), isNotNull);
      expect(validateJson('[1, 2'), isNotNull);
    });

    test('offsetToLineCol', () {
      expect(offsetToLineCol('abc\ndef', 0), (1, 1));
      expect(offsetToLineCol('abc\ndef', 4), (2, 1));
      expect(offsetToLineCol('abc\ndef', 6), (2, 3));
      expect(offsetToLineCol('abc', 99), (1, 4));
    });

    test('format and minify', () {
      expect(formatJson('{"a":[1,2],"b":{"c":true}}'), '{\n  "a": [\n    1,\n    2\n  ],\n  "b": {\n    "c": true\n  }\n}');
      expect(formatJson('{"a":1}', indent: 4), '{\n    "a": 1\n}');
      expect(minifyJson('{ "a" : [ 1 , 2 ] }'), '{"a":[1,2]}');
      expect(formatJson('{bad'), isNull);
      expect(minifyJson('{bad'), isNull);
    });

    test('persian text survives formatting', () {
      final out = formatJson('{"نام":"سلام دنیا"}')!;
      expect(out, contains('سلام دنیا'));
    });
  });

  group('highlighter', () {
    final colors = buildColors(ThemePreset.orange, Brightness.light);
    const base = TextStyle(fontSize: 13);

    String plain(String text, CodeLanguage lang, {bool vars = true, int? error}) => buildHighlightedSpan(
          text: text,
          language: lang,
          colors: colors,
          base: base,
          variables: vars,
          errorOffset: error,
          bracketPair: text.length > 1 ? (0, text.length - 1) : null,
        ).toPlainText();

    test('span text always equals the source', () {
      const samples = <String>[
        '',
        '{"a": 1, "b": [true, false, null], "c": "x\\"y"}',
        '{"unterminated": "abc',
        '{"نام": "سلام {{name}} دنیا", "n": -12.5e+3}',
        '[1,2,3',
        '"line1\nline2"',
        '{{base_url}}/users/{{ id }}',
        '😀 {"emoji": "😀"}',
      ];
      for (final s in samples) {
        expect(plain(s, CodeLanguage.json), s, reason: s);
        expect(plain(s, CodeLanguage.text), s, reason: s);
        expect(plain(s, CodeLanguage.xml), s, reason: s);
        expect(plain(s, CodeLanguage.json, vars: false, error: 3), s, reason: s);
      }
    });

    test('xml and html markup', () {
      const x = '<?xml version="1.0"?>\n<!-- c -->\n<a href="u" id=\'i\'><b>t</b><br/></a>';
      expect(plain(x, CodeLanguage.xml), x);
    });

    test('keys, strings and variables get different colors', () {
      final span = buildHighlightedSpan(
        text: '{"k": "v", "n": 1, "x": {{var}}}',
        language: CodeLanguage.json,
        colors: colors,
        base: base,
      );
      final byText = <String, Color?>{
        for (final c in span.children!.cast<TextSpan>()) c.text!: c.style?.color,
      };
      expect(byText['"k"'], colors.synKey);
      expect(byText['"v"'], colors.synString);
      expect(byText['1'], colors.synNumber);
      expect(byText['{{var}}'], colors.synVariable);
    });

    test('find matches get a background', () {
      final span = buildHighlightedSpan(
        text: 'abcabc',
        language: CodeLanguage.text,
        colors: colors,
        base: base,
        matches: const <TextRange>[TextRange(start: 3, end: 6)],
        currentMatch: 0,
      );
      final kids = span.children!.cast<TextSpan>();
      expect(kids.last.style!.backgroundColor, isNotNull);
      expect(kids.first.style!.backgroundColor, isNull);
    });
  });

  group('bracket matching', () {
    test('matches pairs and skips brackets inside strings', () {
      expect(findBracketPair('{"a":[1]}', 1), (0, 8));
      expect(findBracketPair('{"a":[1]}', 9), (8, 0));
      expect(findBracketPair('{"a(":1}', 1), (0, 7));
      expect(findBracketPair('(()', 0), isNull);
      expect(findBracketPair('abc', 1), isNull);
      expect(findBracketPair('{"a{":1}', 3), isNull);
    });
  });

  group('input formatter', () {
    TextEditingValue v(String t, int caret) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: caret));
    TextEditingValue type(EditorInputFormatter f, TextEditingValue old, String ch) {
      final c = old.selection.baseOffset;
      final next = v(old.text.replaceRange(c, c, ch), c + ch.length);
      return f.formatEditUpdate(old, next);
    }

    final json = EditorInputFormatter(language: CodeLanguage.json, tabSize: 2, autoClose: true);

    test('auto-closes brackets and quotes', () {
      expect(type(json, v('', 0), '{'), v('{}', 1));
      expect(type(json, v('', 0), '['), v('[]', 1));
      expect(type(json, v('', 0), '"'), v('""', 1));
    });

    test('does not close a quote inside a word', () {
      expect(type(json, v('a', 1), '"'), v('a"', 2));
    });

    test('typing a closer steps over the existing one', () {
      expect(type(json, v('{}', 1), '}'), v('{}', 2));
      expect(type(json, v('""', 1), '"'), v('""', 2));
    });

    test('enter keeps indentation and expands braces', () {
      expect(type(json, v('  a', 3), '\n'), v('  a\n  ', 6));
      expect(type(json, v('{}', 1), '\n'), v('{\n  \n}', 4));
      expect(type(json, v('  {', 3), '\n'), v('  {\n    ', 8));
    });

    test('auto close can be disabled but indentation stays', () {
      final f = EditorInputFormatter(language: CodeLanguage.json, tabSize: 4, autoClose: false);
      expect(type(f, v('', 0), '{'), v('{', 1));
      expect(type(f, v('{', 1), '\n'), v('{\n    ', 6));
    });

    test('plain text is never altered', () {
      final f = EditorInputFormatter(language: CodeLanguage.text, tabSize: 2, autoClose: true);
      expect(type(f, v('', 0), '{'), v('{', 1));
      expect(type(f, v('  a', 3), '\n'), v('  a\n', 4));
    });

    test('pasting or multi-character edits are left alone', () {
      final out = json.formatEditUpdate(v('', 0), v('{"a":1}', 7));
      expect(out.text, '{"a":1}');
    });
  });

  group('find and replace', () {
    test('plain, case and regex matching', () {
      expect(findMatches('abcABC', 'abc').length, 2);
      expect(findMatches('abcABC', 'abc', caseSensitive: true).length, 1);
      expect(findMatches('a1b22', r'\d+', regex: true).map((r) => (r.start, r.end)).toList(), <(int, int)>[(1, 2), (3, 5)]);
      expect(findMatches('a.b', '.').length, 1);
      expect(findMatches('abc', ''), isEmpty);
      expect(findMatches('abc', r'x*', regex: true), isEmpty);
    });

    test('invalid regex throws FormatException', () {
      expect(() => findMatches('abc', '(', regex: true), throwsFormatException);
    });

    test('replace all with groups', () {
      expect(replaceAllMatches('a1b2', r'(\w)(\d)', r'$2$1', regex: true), '1a2b');
      expect(replaceAllMatches('a.b.c', '.', '-'), 'a-b-c');
      expect(replaceAllMatches('Aa', 'a', 'x'), 'xx');
      expect(replaceAllMatches('Aa', 'a', 'x', caseSensitive: true), 'Ax');
    });

    test('replace one', () {
      expect(replaceOne('foo bar foo', const TextRange(start: 8, end: 11), 'foo', 'X'), 'foo bar X');
    });
  });

  test('text editing value replace helper keeps selection valid', () {
    const value = TextEditingValue(text: 'abc', selection: TextSelection.collapsed(offset: 1));
    final r = value.replaced(const TextRange(start: 1, end: 1), '  ');
    expect(r.text, 'a  bc');
  });
}
