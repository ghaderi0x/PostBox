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

  Variable copyWith({
    String? key,
    String? value,
    bool? secret,
    bool? enabled,
  }) => Variable(
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

  Environment copyWith({String? name, List<Variable>? variables}) =>
      Environment(
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

/// Where a resolved variable came from (shown by the resolution inspector).
enum VariableSource {
  global,
  collection,
  folder,
  request,
  environment,
  runtime,
}

/// Resolves `{{name}}` placeholders.
///
/// Precedence, highest first: runtime overlay (values extracted by chaining,
/// scripts or the runner), active environment, request, folder (innermost
/// first), collection, global. The environment deliberately beats the whole
/// collection tree so one collection can run against dev and prod.
class VariableResolver {
  VariableResolver({
    Map<String, String> overlay = const <String, String>{},
    Iterable<Variable> environment = const <Variable>[],
    Iterable<Variable> collection = const <Variable>[],
    Iterable<Variable> global = const <Variable>[],
    Iterable<Variable> folder = const <Variable>[],
    Iterable<Variable> request = const <Variable>[],
  }) : _overlay = Map<String, String>.of(overlay),
       _environment = List<Variable>.of(environment),
       _collection = List<Variable>.of(collection),
       _global = List<Variable>.of(global),
       _folder = List<Variable>.of(folder),
       _request = List<Variable>.of(request) {
    final layers = <(VariableSource, Iterable<Variable>)>[
      (VariableSource.global, _global),
      (VariableSource.collection, _collection),
      // Callers pass folders outermost first, so inner folders win.
      (VariableSource.folder, _folder),
      (VariableSource.request, _request),
      (VariableSource.environment, _environment),
    ];
    for (final (source, layer) in layers) {
      for (final v in layer) {
        if (v.enabled && v.key.trim().isNotEmpty) {
          final name = v.key.trim();
          _vars[name] = v;
          _sources[name] = source;
        }
      }
    }
    _overlay.forEach((k, v) {
      _vars[k] = Variable(id: 'overlay:$k', key: k, value: v);
      _sources[k] = VariableSource.runtime;
    });
  }

  final Map<String, String> _overlay;
  final List<Variable> _environment;
  final List<Variable> _collection;
  final List<Variable> _global;
  final List<Variable> _folder;
  final List<Variable> _request;

  /// A resolver with the same layers plus [folder] and [request] variables
  /// and [overlay] values added (overlay entries replace existing ones).
  VariableResolver extended({
    Iterable<Variable> folder = const <Variable>[],
    Iterable<Variable> request = const <Variable>[],
    Map<String, String> overlay = const <String, String>{},
  }) => VariableResolver(
    overlay: <String, String>{..._overlay, ...overlay},
    environment: _environment,
    collection: _collection,
    global: _global,
    folder: <Variable>[..._folder, ...folder],
    request: <Variable>[..._request, ...request],
  );

  /// Runtime values written by chaining or scripts.
  Map<String, String> get overlay => Map<String, String>.unmodifiable(_overlay);

  final Map<String, VariableSource> _sources = <String, VariableSource>{};

  /// Layer that defined [name], or null when it is not defined.
  VariableSource? sourceOf(String name) => _sources[name];

  /// Display value of [name]: the mask for secrets, null when undefined.
  String? displayValue(String name) {
    final v = _vars[name];
    if (v == null) return null;
    return v.secret ? Redactor.mask : v.value;
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
