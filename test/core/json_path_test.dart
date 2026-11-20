import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/util/json_util.dart';

void main() {
  test('builds JSONPath-style paths', () {
    expect(jsonPathFor(const <Object>[]), r'$');
    expect(jsonPathFor(const <Object>['users', 0, 'name']), r'$.users[0].name');
    expect(jsonPathFor(const <Object>['a-b', 'c d']), r"$['a-b']['c d']");
    expect(jsonPathFor(const <Object>["it's"]), r"$['it\'s']");
    expect(jsonPathFor(const <Object>['_ok1', 2, 3]), r'$._ok1[2][3]');
  });
}
