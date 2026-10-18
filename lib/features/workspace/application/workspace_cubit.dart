import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/app_log.dart';
import '../../collections/application/collections_cubit.dart';
import '../../collections/domain/collection_models.dart';
import '../../environments/application/environments_cubit.dart';
import '../../environments/domain/variables.dart';
import '../../history/application/history_cubit.dart';
import '../../http/application/request_executor.dart';
import '../../http/domain/http_engine.dart';
import '../../http/domain/request_builder.dart';
import '../../requests/domain/request_models.dart';
import '../../settings/application/settings_cubit.dart';
import '../../streaming/stream_service.dart';
import '../../../core/util/json_util.dart';

enum SendPhase { idle, sending }

class RequestTab {
  const RequestTab({
    required this.draft,
    this.saved,
    this.collectionId,
    this.phase = SendPhase.idle,
    this.outcome,
    this.events = const <StreamEvent>[],
    this.streaming = false,
    this.previousBody,
  });

  /// Tab id equals the request id.
  String get id => draft.id;

  final RequestModel draft;

  /// The last saved version; null for requests never saved.
  final RequestModel? saved;
  final String? collectionId;
  final SendPhase phase;
  final ExecutionOutcome? outcome;
  final List<StreamEvent> events;
  final bool streaming;

  /// Text of the response before the latest send, for the diff view.
  final String? previousBody;

  bool get isSaved => saved != null;

  bool get dirty {
    final s = saved;
    if (s == null) {
      return draft.url.trim().isNotEmpty ||
          draft.body.isNotEmpty ||
          draft.headers.any((h) => !h.isBlank) ||
          draft.params.any((h) => !h.isBlank);
    }
    return draft.fingerprint() != s.fingerprint();
  }

  RequestTab copyWith({
    RequestModel? draft,
    RequestModel? saved,
    String? collectionId,
    SendPhase? phase,
    ExecutionOutcome? outcome,
    bool clearOutcome = false,
    List<StreamEvent>? events,
    bool? streaming,
    String? previousBody,
    bool clearPrevious = false,
  }) =>
      RequestTab(
        draft: draft ?? this.draft,
        saved: saved ?? this.saved,
        collectionId: collectionId ?? this.collectionId,
        phase: phase ?? this.phase,
        outcome: clearOutcome ? null : (outcome ?? this.outcome),
        events: events ?? this.events,
        streaming: streaming ?? this.streaming,
        previousBody: clearPrevious ? null : (previousBody ?? this.previousBody),
      );
}

class WorkspaceState {
  const WorkspaceState({this.tabs = const <RequestTab>[], this.activeId});
  final List<RequestTab> tabs;
  final String? activeId;

  RequestTab? get active {
    for (final t in tabs) {
      if (t.id == activeId) return t;
    }
    return null;
  }

  RequestTab? tab(String id) {
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }
}

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit({
    required CollectionsCubit collections,
    required EnvironmentsCubit environments,
    required SettingsCubit settings,
    required HistoryCubit history,
    required RequestExecutor executor,
    required AppLog log,
    RequestBuilder builder = const RequestBuilder(),
  })  : _collections = collections,
        _environments = environments,
        _settings = settings,
        _history = history,
        _executor = executor,
        _builder = builder,
        _log = log,
        super(const WorkspaceState());

  final CollectionsCubit _collections;
  final EnvironmentsCubit _environments;
  final SettingsCubit _settings;
  final HistoryCubit _history;
  final RequestExecutor _executor;
  final RequestBuilder _builder;
  final AppLog _log;

  static const int maxStreamEvents = 2000;

  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final Map<String, StreamSession> _sessions = <String, StreamSession>{};
  final Map<String, StreamSubscription<StreamEvent>> _subs =
      <String, StreamSubscription<StreamEvent>>{};

  void _put(String id, RequestTab Function(RequestTab) f) {
    final list = state.tabs.map((t) => t.id == id ? f(t) : t).toList();
    emit(WorkspaceState(tabs: list, activeId: state.activeId));
  }

  VariableResolver resolverFor(RequestTab tab) {
    final env = _environments.state;
    return VariableResolver(
      environment: env.active?.variables ?? const <Variable>[],
      collection: _collections.variablesOf(tab.collectionId),
      global: env.globals,
    );
  }

  void newTab({RequestModel? model, RequestKind kind = RequestKind.http}) {
    final m = model ??
        RequestModel.blank(method: _settings.state.defaultMethod, kind: kind);
    final tab = RequestTab(draft: m);
    emit(WorkspaceState(tabs: <RequestTab>[...state.tabs, tab], activeId: tab.id));
  }

  /// Opens a saved request, or focuses its tab when already open.
  Future<void> openNode(NodeRecord n) async {
    if (n.isFolder) return;
    if (state.tab(n.id) != null) {
      select(n.id);
      _collections.touchOpened(n.id);
      return;
    }
    final full = await _collections.loadFullRequest(n);
    final tab = RequestTab(draft: full, saved: full, collectionId: n.collectionId);
    _collections.touchOpened(n.id);
    emit(WorkspaceState(tabs: <RequestTab>[...state.tabs, tab], activeId: tab.id));
  }

  /// Closes every tab and starts from one blank request (after data was cleared).
  Future<void> reset() async {
    for (final t in state.tabs) {
      await disconnect(t.id);
      _tokens.remove(t.id)?.cancel();
    }
    emit(const WorkspaceState());
    newTab();
  }

  void select(String id) => emit(WorkspaceState(tabs: state.tabs, activeId: id));

  Future<void> closeTab(String id) async {
    await disconnect(id);
    _tokens.remove(id)?.cancel();
    final rest = state.tabs.where((t) => t.id != id).toList();
    var active = state.activeId;
    if (active == id) {
      final idx = state.tabs.indexWhere((t) => t.id == id);
      active = rest.isEmpty ? null : rest[clampInt(idx - 1, 0, rest.length - 1)].id;
    }
    emit(WorkspaceState(tabs: rest, activeId: active));
    if (rest.isEmpty) newTab();
  }

  void update(String id, RequestModel draft) => _put(id, (t) => t.copyWith(draft: draft));

  /// Saves a tab. New requests need [collectionId]; saved ones keep theirs.
  Future<void> save(String id, {String? collectionId, String? parentId}) async {
    final tab = state.tab(id);
    if (tab == null) return;
    final target = tab.collectionId ?? collectionId;
    if (target == null) return;
    await _collections.saveRequest(
      request: tab.draft,
      collectionId: target,
      parentId: parentId,
    );
    _put(id, (t) => t.copyWith(saved: t.draft, collectionId: target));
  }

  Future<void> duplicateTab(String id) async {
    final tab = state.tab(id);
    if (tab == null) return;
    newTab(model: RequestModel.fromJson(tab.draft.toJson(includeSecrets: true)).copyWith(
      id: RequestModel.blank().id,
    ));
  }

  Future<void> send(String id) async {
    final tab = state.tab(id);
    if (tab == null || tab.phase == SendPhase.sending) return;
    if (tab.draft.kind != RequestKind.http) {
      await connect(id);
      return;
    }
    final token = CancelToken();
    _tokens[id] = token;
    // Keep the last response text (up to 1 MB) so the inspector can diff it.
    final last = tab.outcome?.result;
    final previous = last != null && last.body.length <= 1024 * 1024
        ? utf8.decode(last.body, allowMalformed: true)
        : null;
    _put(
      id,
      (t) => t.copyWith(
        phase: SendPhase.sending,
        clearOutcome: true,
        previousBody: previous,
        clearPrevious: previous == null,
      ),
    );

    final settings = _settings.state;
    final outcome = await _executor.execute(
      tab.draft,
      vars: resolverFor(tab),
      settings: settings,
      cancel: token,
    );
    _tokens.remove(id);
    final f = outcome.failure;
    _log.info(
      '${tab.draft.method} ${outcome.request?.preview.url ?? ''} -> '
      '${outcome.result?.statusCode ?? f?.kind.name ?? outcome.buildError?.code}',
    );
    if (state.tab(id) == null) return;

    await _environments.setExtracted(outcome.extracted);
    _history.record(request: tab.draft, outcome: outcome, settings: settings);
    _put(
      id,
      (t) => t.copyWith(
        phase: SendPhase.idle,
        outcome: outcome,
        draft: outcome.updatedAuth == null ? t.draft : t.draft.copyWith(auth: outcome.updatedAuth),
      ),
    );
  }

  void cancel(String id) => _tokens[id]?.cancel();

  // --- SSE and WebSocket -------------------------------------------------

  void _addEvent(String id, StreamEvent e) {
    final tab = state.tab(id);
    if (tab == null) return;
    var events = <StreamEvent>[...tab.events, e];
    if (events.length > maxStreamEvents) {
      events = events.sublist(events.length - maxStreamEvents);
    }
    _put(id, (t) => t.copyWith(events: events));
  }

  Future<void> connect(String id) async {
    final tab = state.tab(id);
    if (tab == null || tab.streaming) return;
    _put(id, (t) => t.copyWith(events: const <StreamEvent>[], streaming: true));
    try {
      final built = await _builder.build(tab.draft, resolverFor(tab), _settings.state);
      final StreamSession session = tab.draft.kind == RequestKind.websocket
          ? await WebSocketSession.connect(built.spec)
          : await SseSession.connect(built.spec);
      _sessions[id] = session;
      _subs[id] = session.events.listen(
        (e) {
          _addEvent(id, e);
          if (e.type == StreamEventType.close || e.type == StreamEventType.error) {
            _put(id, (t) => t.copyWith(streaming: false));
          }
        },
        onDone: () {
          _sessions.remove(id);
          _subs.remove(id);
          if (state.tab(id) != null) _put(id, (t) => t.copyWith(streaming: false));
        },
      );
    } on RequestBuildException catch (e) {
      _addEvent(id, StreamEvent(StreamEventType.error, 'build:${e.code}'));
      _put(id, (t) => t.copyWith(streaming: false));
    } on Exception catch (e) {
      _addEvent(id, StreamEvent(StreamEventType.error, '${e.runtimeType}'));
      _put(id, (t) => t.copyWith(streaming: false));
    }
  }

  Future<void> sendMessage(String id, String text) async {
    final s = _sessions[id];
    if (s != null && text.isNotEmpty) await s.send(text);
  }

  Future<void> disconnect(String id) async {
    final s = _sessions.remove(id);
    final sub = _subs.remove(id);
    await sub?.cancel();
    await s?.close();
    if (state.tab(id) != null) _put(id, (t) => t.copyWith(streaming: false));
  }

  @override
  Future<void> close() async {
    for (final t in _tokens.values) {
      t.cancel();
    }
    for (final s in _sessions.values) {
      await s.close();
    }
    return super.close();
  }
}
