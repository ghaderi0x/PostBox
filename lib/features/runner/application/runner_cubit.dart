import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../collections/application/collections_cubit.dart';
import '../../collections/domain/collection_models.dart';
import '../../collections/domain/node_settings.dart';
import '../../environments/application/environments_cubit.dart';
import '../../environments/domain/variables.dart';
import '../../http/application/request_executor.dart';
import '../../http/domain/http_engine.dart';
import '../../requests/domain/request_models.dart';
import '../../scripting/script_host.dart';
import '../../settings/application/settings_cubit.dart';
import '../../testing/domain/assertions.dart';

class RunResult {
  const RunResult({
    required this.name,
    required this.method,
    required this.url,
    this.status,
    this.durationMs,
    this.error,
    this.assertions = const <AssertionResult>[],
    this.scriptTests = const <ScriptTestResult>[],
    this.iteration = 0,
    required this.passed,
  });

  /// Zero-based iteration (data row) this result belongs to.
  final int iteration;
  final List<ScriptTestResult> scriptTests;
  final String name;
  final String method;
  final String url;
  final int? status;
  final int? durationMs;
  final String? error;
  final List<AssertionResult> assertions;
  final bool passed;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'method': method,
    'url': url,
    'status': status,
    'durationMs': durationMs,
    'error': error,
    'passed': passed,
    'iteration': iteration,
    'scriptTests': scriptTests
        .map((t) => <String, dynamic>{'name': t.name, 'passed': t.passed})
        .toList(),
    'assertions': assertions
        .map(
          (a) => <String, dynamic>{
            'kind': a.assertion.kind.name,
            'passed': a.passed,
            'message': a.message,
          },
        )
        .toList(),
  };
}

class RunnerState {
  const RunnerState({
    this.running = false,
    this.total = 0,
    this.results = const <RunResult>[],
    this.collectionName = '',
    this.iterations = 1,
  });

  final int iterations;
  final bool running;
  final int total;
  final List<RunResult> results;
  final String collectionName;

  int get passed => results.where((r) => r.passed).length;
  int get failed => results.length - passed;

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# PostBox run report: $collectionName')
      ..writeln()
      ..writeln('Passed: $passed, failed: $failed, total: ${results.length}')
      ..writeln()
      ..writeln('| Iteration | Result | Method | URL | Status | ms | Notes |')
      ..writeln('|---|---|---|---|---|---|---|');
    for (final r in results) {
      final notes = <String>[
        if (r.error != null) r.error!,
        ...r.assertions
            .where((a) => !a.passed)
            .map((a) => '${a.assertion.kind.name}: ${a.message}'),
        ...r.scriptTests.where((t) => !t.passed).map((t) => 'test: ${t.name}'),
      ].join('; ');
      b.writeln(
        '| ${r.iteration + 1} | ${r.passed ? 'PASS' : 'FAIL'} | ${r.method} | ${r.url.replaceAll('|', r'\|')} | ${r.status ?? ''} | ${r.durationMs ?? ''} | ${notes.replaceAll('|', r'\|')} |',
      );
    }
    return b.toString();
  }

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'collection': collectionName,
        'iterations': iterations,
        'passed': passed,
        'failed': failed,
        'results': results.map((r) => r.toJson()).toList(),
      });
}

/// Runs the requests of a collection in order. Values extracted by one request
/// are available to later ones through an in-memory overlay; nothing is
/// written to environments.
class RunnerCubit extends Cubit<RunnerState> {
  RunnerCubit({
    required CollectionsCubit collections,
    required EnvironmentsCubit environments,
    required SettingsCubit settings,
    required RequestExecutor executor,
  }) : _collections = collections,
       _environments = environments,
       _settings = settings,
       _executor = executor,
       super(const RunnerState());

  final CollectionsCubit _collections;
  final EnvironmentsCubit _environments;
  final SettingsCubit _settings;
  final RequestExecutor _executor;

  final Set<CancelToken> _tokens = <CancelToken>{};
  bool _stop = false;

  List<NodeRecord> requestsOf(String collectionId) {
    final out = <NodeRecord>[];
    void walk(String? parent) {
      for (final n in _collections.state.childrenOf(collectionId, parent)) {
        if (n.isFolder) {
          walk(n.id);
        } else {
          out.add(n);
        }
      }
    }

    walk(null);
    return out;
  }

  /// Runs the collection once per iteration. Each iteration runs the requests
  /// in order with its own in-memory variables (so chaining works inside an
  /// iteration); up to [concurrency] iterations run at the same time.
  ///
  /// With [data], every row is one iteration and its columns become
  /// variables. Without data, [iterations] repeats the same run. Nothing is
  /// written to environments.
  Future<void> run(
    String collectionId, {
    bool stopOnFailure = false,
    int iterations = 1,
    int concurrency = 1,
    List<Map<String, String>> data = const <Map<String, String>>[],
  }) async {
    if (state.running) return;
    final col = _collections.state.collection(collectionId);
    if (col == null) return;
    final nodes = requestsOf(collectionId);
    final count = data.isNotEmpty
        ? data.length
        : math.max(1, math.min(iterations, 1000));
    final workers = math.max(1, math.min(math.min(concurrency, 10), count));
    _stop = false;
    emit(
      RunnerState(
        running: true,
        total: nodes.length * count,
        collectionName: col.name,
        iterations: count,
      ),
    );

    // Load requests and what they inherit once; iterations share them.
    final requests = <RequestModel>[];
    final contexts = <EffectiveContext>[];
    for (final n in nodes) {
      requests.add(await _collections.loadFullRequest(n));
      contexts.add(
        await _collections.effectiveContext(
          collectionId: collectionId,
          parentId: n.parentId,
        ),
      );
    }

    final results = <RunResult>[];
    final settings = _settings.state;
    final env = _environments.state;

    void publish({required bool running}) => emit(
      RunnerState(
        running: running,
        total: nodes.length * count,
        results: List<RunResult>.of(results),
        collectionName: col.name,
        iterations: count,
      ),
    );

    Future<void> runIteration(int iteration) async {
      final overlay = <String, String>{if (data.isNotEmpty) ...data[iteration]};
      for (var i = 0; i < nodes.length; i++) {
        if (_stop) return;
        final req = requests[i];
        final vars = VariableResolver(
          overlay: overlay,
          environment: env.active?.variables ?? const <Variable>[],
          collection: col.variables,
          global: env.globals,
        );
        final token = CancelToken();
        _tokens.add(token);
        final o = await _executor.execute(
          req,
          vars: vars,
          settings: settings,
          cancel: token,
          inherited: contexts[i],
        );
        _tokens.remove(token);
        overlay.addAll(o.extracted);

        final res = o.result;
        final passed =
            o.ok &&
            o.assertionsPassed &&
            (o.hasChecks || res!.statusCode < 400);
        results.add(
          RunResult(
            name: nodes[i].name,
            method: req.method.toUpperCase(),
            url: o.request?.preview.url ?? req.url,
            status: res?.statusCode,
            durationMs: res?.duration.inMilliseconds,
            error:
                o.buildError?.code ??
                o.failure?.kind.name ??
                (o.scriptError != null && res == null ? 'script' : null),
            assertions: o.assertions,
            scriptTests: o.scriptTests,
            iteration: iteration,
            passed: passed,
          ),
        );
        publish(running: true);
        if (stopOnFailure && !passed) {
          _stop = true;
          return;
        }
      }
    }

    var next = 0;
    Future<void> worker() async {
      while (!_stop) {
        final i = next++;
        if (i >= count) return;
        await runIteration(i);
      }
    }

    await Future.wait(<Future<void>>[
      for (var w = 0; w < workers; w++) worker(),
    ]);
    _tokens.clear();
    publish(running: false);
  }

  void stop() {
    _stop = true;
    for (final t in _tokens.toList()) {
      t.cancel();
    }
  }
}
