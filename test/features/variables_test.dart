import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/environments/domain/variables.dart';

Variable v(String k, String val, {bool secret = false, bool enabled = true}) =>
    Variable(id: 'id-$k-$val', key: k, value: val, secret: secret, enabled: enabled);

void main() {
  test('precedence: overlay > environment > collection > global', () {
    final r = VariableResolver(
      overlay: <String, String>{'a': 'overlay'},
      environment: <Variable>[v('a', 'env'), v('b', 'env')],
      collection: <Variable>[v('a', 'col'), v('b', 'col'), v('c', 'col')],
      global: <Variable>[v('a', 'glob'), v('b', 'glob'), v('c', 'glob'), v('d', 'glob')],
    );
    expect(r.resolve('{{a}} {{b}} {{c}} {{d}}').text, 'overlay env col glob');
  });

  test('reports unresolved names and keeps the placeholder', () {
    final r = VariableResolver(environment: <Variable>[v('x', '1')]);
    final res = r.resolve('{{x}}/{{ y }}/{{z}}');
    expect(res.text, '1/{{ y }}/{{z}}');
    expect(res.unresolved, <String>{'y', 'z'});
  });

  test('disabled and blank-key variables are ignored', () {
    final r = VariableResolver(environment: <Variable>[v('a', '1', enabled: false), v('', 'x')]);
    expect(r.resolve('{{a}}').unresolved, <String>{'a'});
  });

  test('secret values are masked on request', () {
    final r = VariableResolver(environment: <Variable>[v('token', 's3cret', secret: true), v('host', 'h')]);
    expect(r.resolve('{{token}}@{{host}}').text, 's3cret@h');
    expect(r.resolve('{{token}}@{{host}}', maskSecrets: true).text, '••••@h');
    expect(r.isSecret('token'), isTrue);
    expect(r.isSecret('host'), isFalse);
  });

  test('toJson never contains secret values by default', () {
    final secret = v('t', 'abc', secret: true);
    expect(secret.toJson()['value'], '');
    expect(secret.toJson(includeSecretValue: true)['value'], 'abc');
    expect(Variable.fromJson(secret.toJson(includeSecretValue: true)).value, 'abc');
  });
}
