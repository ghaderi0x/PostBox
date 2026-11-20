import '../../../core/model/key_value.dart';
import '../../../core/util/json_util.dart';
import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';

/// Settings that a collection or a folder passes down to everything below it.
///
/// * [auth] with type [AuthType.inherit] means "not set here, ask the parent".
///   [AuthType.none] is an explicit "no authentication below this point".
/// * [headers] are added to every request below unless the request defines a
///   header with the same name.
/// * [variables] of folders sit between collection and request in precedence.
///   Collections keep their variables in their own field for compatibility.
/// * Scripts run before / after the request's own script (see
///   [InheritanceResolver] for the order).
class NodeSettings {
  const NodeSettings({
    this.variables = const <Variable>[],
    this.headers = const <KeyValue>[],
    this.auth = const AuthConfig(type: AuthType.inherit),
    this.preScript = '',
    this.postScript = '',
  });

  static const NodeSettings empty = NodeSettings();

  final List<Variable> variables;
  final List<KeyValue> headers;
  final AuthConfig auth;
  final String preScript;
  final String postScript;

  bool get isEmpty =>
      variables.isEmpty &&
      headers.isEmpty &&
      auth.type == AuthType.inherit &&
      preScript.trim().isEmpty &&
      postScript.trim().isEmpty;

  NodeSettings copyWith({
    List<Variable>? variables,
    List<KeyValue>? headers,
    AuthConfig? auth,
    String? preScript,
    String? postScript,
  }) => NodeSettings(
    variables: variables ?? this.variables,
    headers: headers ?? this.headers,
    auth: auth ?? this.auth,
    preScript: preScript ?? this.preScript,
    postScript: postScript ?? this.postScript,
  );

  /// Copy without secret values, for state held in memory and the database.
  NodeSettings stripped() => copyWith(
    variables: variables
        .map((v) => v.secret ? v.copyWith(value: '') : v)
        .toList(),
    auth: auth.withoutSecrets(),
  );

  /// Database and default-export form: no secret values anywhere.
  Map<String, dynamic> toJson({bool includeSecrets = false}) =>
      <String, dynamic>{
        'variables': variables
            .map((v) => v.toJson(includeSecretValue: includeSecrets))
            .toList(),
        'headers': KeyValue.listToJson(headers),
        'auth': auth.toJson(includeSecrets: includeSecrets),
        if (preScript.isNotEmpty) 'preScript': preScript,
        if (postScript.isNotEmpty) 'postScript': postScript,
      };

  factory NodeSettings.fromJson(Object? j) {
    final m = asMap(j);
    if (m.isEmpty) return NodeSettings.empty;
    return NodeSettings(
      variables: Variable.listFromJson(m['variables']),
      headers: KeyValue.listFromJson(m['headers']),
      auth: m.containsKey('auth')
          ? AuthConfig.fromJson(m['auth'])
          : const AuthConfig(type: AuthType.inherit),
      preScript: asString(m['preScript']),
      postScript: asString(m['postScript']),
    );
  }
}

/// What a request receives from the collection and folders above it.
/// Built from the outermost level (collection) to the innermost folder.
class EffectiveContext {
  const EffectiveContext({
    this.auth,
    this.authSource,
    this.headers = const <KeyValue>[],
    this.folderVariables = const <Variable>[],
    this.preScripts = const <String>[],
    this.postScripts = const <String>[],
  });

  static const EffectiveContext none = EffectiveContext();

  /// Resolved auth for a request with [AuthType.inherit]; null when nothing
  /// above the request defines one (the request then sends no auth).
  final AuthConfig? auth;

  /// Name of the collection or folder that supplied [auth].
  final String? authSource;

  /// Inherited headers, outermost first; later entries override earlier ones.
  final List<KeyValue> headers;

  /// Folder variables, outermost first (inner folders win).
  final List<Variable> folderVariables;

  /// Scripts to run before the request: outermost first.
  final List<String> preScripts;

  /// Scripts to run after the response: innermost first.
  final List<String> postScripts;
}

/// One level of the chain: a collection or a folder with a display name.
class SettingsLevel {
  const SettingsLevel(this.name, this.settings);
  final String name;
  final NodeSettings settings;
}

/// Merges collection and folder settings into what a request inherits.
class InheritanceResolver {
  const InheritanceResolver._();

  /// [chain] is ordered outermost first: collection, folder, subfolder, ...
  static EffectiveContext resolve(List<SettingsLevel> chain) {
    AuthConfig? auth;
    String? authSource;
    final headers = <KeyValue>[];
    final vars = <Variable>[];
    final pre = <String>[];
    final post = <String>[];
    for (final level in chain) {
      final s = level.settings;
      if (s.auth.type != AuthType.inherit) {
        // Inner levels overwrite outer ones.
        auth = s.auth;
        authSource = level.name;
      }
      headers.addAll(
        s.headers.where((h) => h.enabled && h.key.trim().isNotEmpty),
      );
      vars.addAll(s.variables);
      if (s.preScript.trim().isNotEmpty) pre.add(s.preScript);
      if (s.postScript.trim().isNotEmpty) post.add(s.postScript);
    }
    return EffectiveContext(
      auth: auth,
      authSource: authSource,
      headers: headers,
      folderVariables: vars,
      preScripts: pre,
      postScripts: post.reversed.toList(),
    );
  }

  /// Applies inheritance to [r]: replaces an inherited auth and merges
  /// inherited headers underneath the request's own headers. Scripts and
  /// variables are handled by the executor.
  static RequestModel apply(RequestModel r, EffectiveContext ctx) {
    var out = r;
    if (r.auth.type == AuthType.inherit) {
      out = out.copyWith(auth: ctx.auth ?? const AuthConfig());
    }
    if (ctx.headers.isNotEmpty) {
      final own = <String>{
        for (final h in r.headers)
          if (h.enabled) h.key.trim().toLowerCase(),
      };
      // Later inherited entries win over earlier ones with the same name.
      final byName = <String, KeyValue>{};
      for (final h in ctx.headers) {
        byName[h.key.trim().toLowerCase()] = h;
      }
      final inherited = byName.entries
          .where((e) => !own.contains(e.key))
          .map((e) => e.value)
          .toList();
      out = out.copyWith(headers: <KeyValue>[...inherited, ...r.headers]);
    }
    return out;
  }
}
