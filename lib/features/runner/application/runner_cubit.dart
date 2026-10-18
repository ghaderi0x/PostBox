import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../collections/application/collections_cubit.dart';
import '../../collections/domain/collection_models.dart';
import '../../environments/application/environments_cubit.dart';
import '../../environments/domain/variables.dart';
import '../../http/application/request_executor.dart';
import '../../http/domain/http_engine.dart';
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
    required this.passed,
  });

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
        'assertions': assertions
            .map((a) => <String, dynamic>{
                  'kind': a.assertion.kind.name,
                  'passed': a.passed,
                  'message': a.message,
                })
            .toList(),
      };
}

class RunnerState {
  const RunnerState({
    this.running = false,
    this.total = 0,
    this.results = const <RunResult>[],
    this.collectionName = '',
  });

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
      ..writeln('| Result | Method | URL | Status | ms | Notes |')
      ..writeln('|---|---|---|---|---|---|');
    for (final r in results) {
      final notes = <String>[
        if (r.error != null) r.error!,
        ...r.assertions.where((a) => !a.passed).map((a) => '${a.assertion.kind.name}: ${a.message}'),
      ].join('; ');
      b.writeln('| ${r.passed ? 'PASS' : 'FAIL'} | ${r.method} | ${r.url.replaceAll('|', r'\|')} | ${r.status ?? ''} | ${r.durationMs ?? ''} | ${notes.replaceAll('|', r'\|')} |');
    }
    return b.toString();
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'collection': collectionName,
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
  })  : _collections = collections,
        _environments = environments,
        _settings = settings,
        _executor = executor,
        super(const RunnerState());

  final CollectionsCubit _collections;
  final EnvironmentsCubit _environments;
  final SettingsCubit _settings;
  final RequestExecutor _executor;

  CancelToken? _token;
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

  Future<void> run(String collectionId, {bool stopOnFailure = false}) async {
    if (state.running) return;
    final col = _collections.state.collection(collectionId);
    if (col == null) return;
    final nodes = requestsOf(collectionId);
    _stop = false;
    emit(RunnerState(running: true, total: nodes.length, collectionName: col.name));

    final overlay = <String, String>{};
    final results = <RunResult>[];
    final settings = _settings.state;
    final env = _environments.state;

    for (final n in nodes) {
      if (_stop) break;
      final req = await _collections.loadFullRequest(n);
      final vars = VariableResolver(
        overlay: overlay,
        environment: env.active?.variables ?? const <Variable>[],
        collection: col.variables,
        global: env.globals,
      );
      _token = CancelToken();
      final o = await _executor.execute(req, vars: vars, settings: settings, cancel: _token);
      overlay.addAll(o.extracted);

      final res = o.result;
      final noAssertions = o.assertions.isEmpty;
      final passed = o.ok &&
          o.assertionsPassed &&
          (!noAssertions || res!.statusCode < 400);
      results.add(RunResult(
        name: n.name,
        method: req.method.toUpperCase(),
        url: o.request?.preview.url ?? req.url,
        status: res?.statusCode,
        durationMs: res?.duration.inMilliseconds,
        error: o.buildError?.code ?? o.failure?.kind.name,
        assertions: o.assertions,
        passed: passed,
      ));
      emit(RunnerState(
        running: true,
        total: nodes.length,
        results: List<RunResult>.of(results),
        collectionName: col.name,
      ));
      if (stopOnFailure && !passed) break;
    }
    _token = null;
    emit(RunnerState(
      running: false,
      total: nodes.length,
      results: results,
      collectionName: col.name,
    ));
  }

  void stop() {
    _stop = true;
    _token?.cancel();
  }
}
