import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/testing/domain/line_diff.dart';

String render(List<DiffLine> d) => d
    .map((l) => '${l.op == DiffOp.same ? ' ' : (l.op == DiffOp.added ? '+' : '-')}${l.text}')
    .join('|');

void main() {
  test('identical input has only unchanged lines', () {
    expect(render(lineDiff(<String>['a', 'b'], <String>['a', 'b'])!), ' a| b');
  });

  test('additions, removals and replacements', () {
    expect(render(lineDiff(<String>['a', 'b', 'c'], <String>['a', 'x', 'c'])!), ' a|-b|+x| c');
    expect(render(lineDiff(<String>['a'], <String>['a', 'b'])!), ' a|+b');
    expect(render(lineDiff(<String>['a', 'b'], <String>['b'])!), '-a| b');
    expect(render(lineDiff(<String>[], <String>['x'])!), '+x');
    expect(render(lineDiff(<String>['x'], <String>[])!), '-x');
  });

  test('keeps the longest common subsequence', () {
    final d = lineDiff(<String>['1', '2', '3', '4'], <String>['2', '4', '5'])!;
    expect(render(d), '-1| 2|-3| 4|+5');
  });

  test('returns null when the changed region is too large', () {
    final a = List<String>.generate(100, (i) => 'a$i');
    final b = List<String>.generate(100, (i) => 'b$i');
    expect(lineDiff(a, b, maxCells: 50), isNull);
    expect(lineDiff(a, b), isNotNull);
  });
}
