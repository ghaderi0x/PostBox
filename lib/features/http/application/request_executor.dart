import '../../auth/oauth_service.dart';
import '../../collections/domain/node_settings.dart';
import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';
import '../../scripting/script_host.dart';
import '../../secrets/secret_store.dart';
import '../../settings/domain/app_settings.dart';
import '../../testing/domain/assertions.dart';
import '../domain/cookie_jar.dart';
import '../domain/http_engine.dart';
import '../domain/request_builder.dart';

class ExecutionOutcome {
  const ExecutionOutcome({
    this.request,
    this.result,
    this.failure,
    this.buildError,
    this.assertions = const <AssertionResult>[],
    this.extracted = const <String, String>{},
    this.updatedAuth,
    this.scriptTests = const <ScriptTestResult>[],
    this.scriptLogs = const <String>[],
    this.scriptError,
    this.effectiveAuthSource,
  });

  final BuiltRequest? request;
  final HttpResult? result;
  final HttpFailure? failure;

  /// Stable code (and detail) when the request could not be built.
  final RequestBuildException? buildError;
  final List<AssertionResult> assertions;

  /// Values extracted by the request's extractions and set by scripts with
  /// `vars.set`. The workspace stores them in the active environment (or the
  /// globals), like extractions; the runner keeps them in memory per iteration.
  final Map<String, String> extracted;

  /// Set when OAuth tokens were refreshed so the caller can persist them.
  final AuthConfig? updatedAuth;

  final List<ScriptTestResult> scriptTests;
  final List<String> scriptLogs;

  /// A script failed to parse or run. A failing pre-request script stops the
  /// request from being sent; a failing post-response script keeps the response.
  final String? scriptError;

  /// Name of the collection or folder whose auth was used (inherit), if any.
  final String? effectiveAuthSource;

  bool get ok => result != null;
  bool get assertionsPassed =>
      assertions.every((a) => a.passed) &&
      scriptTests.every((t) => t.passed) &&
      scriptError == null;

  /// True when the request had any assertion or script test.
  bool get hasChecks => assertions.isNotEmpty || scriptTests.isNotEmpty;
}

/// Builds, sends and post-processes one request. Never retries automatically.
///
/// Order: apply inherited auth and headers, run pre-request scripts, refresh
/// an expiring OAuth token, build, send, evaluate assertions and extractions,
/// run post-response scripts.
class RequestExecutor {
  RequestExecutor({
    required HttpEngine engine,
    RequestBuilder builder = const RequestBuilder(),
    OAuthService? oauth,
    CookieJar? cookieJar,
    SecretStore? secrets,
    ScriptRunner scripts = const ScriptRunner(),
  }) : _engine = engine,
       _builder = builder,
       _oauth = oauth,
       _cookieJar = cookieJar,
       _secrets = secrets,
       _scripts = scripts;

  final HttpEngine _engine;
  final RequestBuilder _builder;
  final OAuthService? _oauth;
  final CookieJar? _cookieJar;
  final SecretStore? _secrets;
  final ScriptRunner _scripts;

  /// Request-level variables as resolver input.
  static List<Variable> requestVariables(RequestModel r) => <Variable>[
    for (final kv in r.variables)
      if (kv.enabled && kv.key.trim().isNotEmpty)
        Variable(
          id: 'request:${kv.key.trim()}',
          key: kv.key.trim(),
          value: kv.value,
        ),
  ];

  Future<ExecutionOutcome> execute(
    RequestModel request, {
    required VariableResolver vars,
    required AppSettings settings,
    CancelToken? cancel,
    EffectiveContext inherited = EffectiveContext.none,
  }) async {
    final usesInheritedAuth = request.auth.type == AuthType.inherit;
    final authSource = usesInheritedAuth ? inherited.authSource : null;

    var req = InheritanceResolver.apply(request, inherited);
    var resolver = vars.extended(
      folder: inherited.folderVariables,
      request: requestVariables(req),
    );

    // Pre-request scripts: collection, folders, then the request itself.
    final pre = _scripts.runPre(
      scripts: <String>[...inherited.preScripts, req.preScript],
      request: req,
      vars: resolver,
    );
    req = pre.$1;
    final script = pre.$2;
    if (script.error != null) {
      return ExecutionOutcome(
        scriptError: script.error,
        scriptLogs: script.logs,
        scriptTests: script.tests,
        extracted: script.variableWrites,
        effectiveAuthSource: authSource,
      );
    }
    if (script.variableWrites.isNotEmpty) {
      resolver = resolver.extended(overlay: script.variableWrites);
    }

    AuthConfig? updatedAuth;
    final a = req.auth;
    // Inherited OAuth tokens belong to the collection or folder; they are not
    // refreshed behind the user's back (re-authorize in its auth settings).
    if (!usesInheritedAuth &&
        a.type == AuthType.oauth2 &&
        _oauth != null &&
        a.accessToken.isNotEmpty &&
        a.refreshToken.isNotEmpty &&
        a.expiresAtMs > 0 &&
        a.expiresAtMs < DateTime.now().millisecondsSinceEpoch + 15000) {
      try {
        final t = await _oauth.refresh(a);
        updatedAuth = a.copyWith(
          accessToken: t.accessToken,
          refreshToken: t.refreshToken,
          expiresAtMs: t.expiresAtMs,
        );
        req = req.copyWith(auth: updatedAuth);
      } on OAuthException {
        // Keep the old token; the server decides. The user can re-authorize.
      }
    }

    String? keyPassword;
    if (settings.clientCertPath.isNotEmpty && _secrets != null) {
      keyPassword = await _secrets.read(kClientKeyPasswordSecret);
    }

    final BuiltRequest built;
    try {
      built = await _builder.build(
        req,
        resolver,
        settings,
        cookieJar: _cookieJar,
        clientKeyPassword: keyPassword,
      );
    } on RequestBuildException catch (e) {
      return ExecutionOutcome(
        buildError: e,
        updatedAuth: updatedAuth,
        scriptLogs: script.logs,
        scriptTests: script.tests,
        extracted: script.variableWrites,
        effectiveAuthSource: authSource,
      );
    }

    final HttpResult res;
    try {
      res = await _engine.send(built.spec, cancel: cancel);
    } on HttpFailure catch (f) {
      return ExecutionOutcome(
        request: built,
        failure: f,
        updatedAuth: updatedAuth,
        scriptLogs: script.logs,
        scriptTests: script.tests,
        extracted: script.variableWrites,
        effectiveAuthSource: authSource,
      );
    }

    final extracted = <String, String>{
      ...script.variableWrites,
      ...applyExtractions(req.extractions, res),
    };

    // Post-response scripts see the extractions made so far.
    final post = _scripts.runPost(
      scripts: <String>[req.postScript, ...inherited.postScripts],
      request: req,
      vars: resolver.extended(overlay: extracted),
      response: res,
    );
    extracted.addAll(post.variableWrites);

    return ExecutionOutcome(
      request: built,
      result: res,
      assertions: evaluateAssertions(req.assertions, res),
      extracted: extracted,
      updatedAuth: updatedAuth,
      scriptTests: <ScriptTestResult>[...script.tests, ...post.tests],
      scriptLogs: <String>[...script.logs, ...post.logs],
      scriptError: post.error,
      effectiveAuthSource: authSource,
    );
  }
}
