import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/ids.dart';
import '../../../core/util/redact.dart';
import '../../http/application/request_executor.dart';
import '../../requests/domain/request_models.dart';
import '../../settings/domain/app_settings.dart';
import '../data/history_repository.dart';
import '../domain/history_models.dart';

class HistoryState {
  const HistoryState({this.entries = const <HistoryEntry>[], this.query = ''});
  final List<HistoryEntry> entries;
  final String query;
}

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._repo) : super(const HistoryState());

  final HistoryRepository _repo;

  void refresh() => emit(
    HistoryState(
      entries: _repo.list(query: state.query),
      query: state.query,
    ),
  );

  void setQuery(String q) => emit(
    HistoryState(
      entries: _repo.list(query: q),
      query: q,
    ),
  );

  void delete(String id) {
    _repo.delete(id);
    refresh();
  }

  void clear() {
    _repo.clear();
    refresh();
  }

  /// Records one finished request according to the privacy settings. Cancelled
  /// requests and build errors are not recorded.
  void record({
    required RequestModel request,
    required ExecutionOutcome outcome,
    required AppSettings settings,
  }) {
    if (!settings.persistHistory) return;
    final failure = outcome.failure;
    if (outcome.buildError != null) return;
    // A failed pre-request script means nothing was sent.
    if (outcome.scriptError != null &&
        outcome.result == null &&
        failure == null) {
      return;
    }
    if (failure != null && failure.kind.name == 'cancelled') return;

    final rawUrl = outcome.request?.preview.url ?? request.url;
    final omit = settings.omitSensitiveInHistory;
    final entry = HistoryEntry(
      id: newId(),
      ts: DateTime.now().millisecondsSinceEpoch,
      method: request.method.toUpperCase(),
      url: omit ? Redactor.url(rawUrl) : rawUrl,
      status: outcome.result?.statusCode,
      durationMs: outcome.result?.duration.inMilliseconds,
      size: outcome.result?.body.length,
      error: failure?.kind.name,
      requestJson: omit ? null : jsonEncode(request.toJson()),
    );
    _repo.add(entry);
    _repo.prune(
      maxAgeDays: settings.historyRetentionDays,
      maxEntries: settings.historyMaxEntries,
    );
    refresh();
  }

  void prune(AppSettings settings) {
    _repo.prune(
      maxAgeDays: settings.historyRetentionDays,
      maxEntries: settings.historyMaxEntries,
    );
    refresh();
  }
}
