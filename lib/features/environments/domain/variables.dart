import '../../../core/util/ids.dart';
import '../../../core/util/json_util.dart';
import '../../../core/util/redact.dart';

class Variable {
  const Variable({
    required this.id,
    this.key = '',
    this.value = '',
    this.secret = false,
    this.enabled = true,
  });

  final String id;
  final String key;
  final String value;

  /// Secret values live in secure storage; the database keeps only metadata.
  final bool secret;
  final bool enabled;

  factory Variable.blank() => Variable(id: newId());

  Variable copyWith({String? key, String? value, bool? secret, bool? enabled}) =>
      Variable(
        id: id,
        key: key ?? this.key,
        value: value ?? this.value,
        secret: secret ?? this.secret,
        enabled: enabled ?? this.enabled,
      );

  /// [includeSecretValue] is false for database rows and default exports.
  Map<String, dynamic> toJson({bool includeSecretValue = false}) =>
      <String, dynamic>{
        'id': id,
        'key': key,
        'value': secret && !includeSecretValue ? '' : value,
        'secret': secret,
        'enabled': enabled,
      };

  factory Variable.fromJson(Object? j) {
    final m = asMap(j);
    return Variable(
      id: asString(m['id']).isEmpty ? newId() : asString(m['id']),
      key: asString(m['key']),
      value: asString(m['value']),
      secret: asBool(m['secret'], false),
      enabled: asBool(m['enabled'], true),
    );
  }

  static List<Variable> listFromJson(Object? j) =>
      asList(j).map(Variable.fromJson).toList();
}

class Environment {
  const Environment({
    required this.id,
    required this.name,
    this.variables = const <Variable>[],
  });

  final String id;
  final String name;
  final List<Variable> variables;

  Environment copyWith({String? name, List<Variable>? variables}) => Environment(
        id: id,
        name: name ?? this.name,
        variables: variables ?? this.variables,
      );
}

class ResolveResult {
  const ResolveResult(this.text, this.unresolved);
  final String text;
  final Set<String> unresolved;
}

final RegExp kVariablePattern = RegExp(r'\{\{\s*([A-Za-z0-9_.\-]+)\s*\}\}');

/// Resolves `{{name}}` placeholders.
///
/// Precedence, highest first: runtime overlay (values extracted by chaining or
/// the runner), active environment, collection, global.
class VariableResolver {
  VariableResolver({
    Map<String, String> overlay = const <String, String>{},
    Iterable<Variable> environment = const <Variable>[],
    Iterable<Variable> collection = const <Variable>[],
    Iterable<Variable> global = const <Variable>[],
  }) {
    for (final layer in <Iterable<Variable>>[global, collection, environment]) {
      for (final v in layer) {
        if (v.enabled && v.key.trim().isNotEmpty) {
          _vars[v.key.trim()] = v;
        }
      }
    }
    overlay.forEach((k, v) {
      _vars[k] = Variable(id: 'overlay:$k', key: k, value: v);
    });
  }

  final Map<String, Variable> _vars = <String, Variable>{};

  Iterable<String> get names => _vars.keys;

  bool isSecret(String name) => _vars[name]?.secret ?? false;

  /// With [maskSecrets], secret variables render as the mask so previews and
  /// logs never contain them.
  ResolveResult resolve(String input, {bool maskSecrets = false}) {
    if (!input.contains('{{')) return ResolveResult(input, const <String>{});
    final unresolved = <String>{};
    final text = input.replaceAllMapped(kVariablePattern, (m) {
      final name = m[1]!;
      final v = _vars[name];
      if (v == null) {
        unresolved.add(name);
        return m[0]!;
      }
      return maskSecrets && v.secret ? Redactor.mask : v.value;
    });
    return ResolveResult(text, unresolved);
  }

  Set<String> findUnresolved(String input) => resolve(input).unresolved;
}
