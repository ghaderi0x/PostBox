import '../../auth/oauth_service.dart';
import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';
import '../../settings/domain/app_settings.dart';
import '../../testing/domain/assertions.dart';
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
  });

  final BuiltRequest? request;
  final HttpResult? result;
  final HttpFailure? failure;

  /// Stable code (and detail) when the request could not be built.
  final RequestBuildException? buildError;
  final List<AssertionResult> assertions;
  final Map<String, String> extracted;

  /// Set when OAuth tokens were refreshed so the caller can persist them.
  final AuthConfig? updatedAuth;

  bool get ok => result != null;
  bool get assertionsPassed => assertions.every((a) => a.passed);
}

/// Builds, sends and post-processes one request. Never retries automatically.
class RequestExecutor {
  RequestExecutor({
    required HttpEngine engine,
    RequestBuilder builder = const RequestBuilder(),
    OAuthService? oauth,
  })  : _engine = engine,
        _builder = builder,
        _oauth = oauth;

  final HttpEngine _engine;
  final RequestBuilder _builder;
  final OAuthService? _oauth;

  Future<ExecutionOutcome> execute(
    RequestModel request, {
    required VariableResolver vars,
    required AppSettings settings,
    CancelToken? cancel,
  }) async {
    var req = request;
    AuthConfig? updatedAuth;

    final a = req.auth;
    if (a.type == AuthType.oauth2 &&
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

    final BuiltRequest built;
    try {
      built = await _builder.build(req, vars, settings);
    } on RequestBuildException catch (e) {
      return ExecutionOutcome(buildError: e, updatedAuth: updatedAuth);
    }

    try {
      final res = await _engine.send(built.spec, cancel: cancel);
      return ExecutionOutcome(
        request: built,
        result: res,
        assertions: evaluateAssertions(req.assertions, res),
        extracted: applyExtractions(req.extractions, res),
        updatedAuth: updatedAuth,
      );
    } on HttpFailure catch (f) {
      return ExecutionOutcome(request: built, failure: f, updatedAuth: updatedAuth);
    }
  }
}
