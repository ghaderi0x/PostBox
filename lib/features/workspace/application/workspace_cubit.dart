import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/app_log.dart';
import '../../collections/application/collections_cubit.dart';
import '../../collections/domain/collection_models.dart';
import '../../collections/domain/node_settings.dart';
import '../../environments/application/environments_cubit.dart';
import '../../environments/domain/variables.dart';
import '../../history/application/history_cubit.dart';
import '../../http/application/request_executor.dart';
import '../../http/domain/http_engine.dart';
import '../../http/domain/request_builder.dart';
import '../../requests/domain/request_models.dart';
import '../../settings/application/settings_cubit.dart';
import '../../streaming/stream_service.dart';
import '../data/session_store.dart';
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
  }) => RequestTab(
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
    SessionStore? session,
    RequestBuilder builder = const RequestBuilder(),
  }) : _session = session,
       _collections = collections,
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
  final SessionStore? _session;
  Timer? _persistTimer;
  bool _restoring = false;

  static const int maxStreamEvents = 2000;
  static const int maxRestoredTabs = 30;

  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final Map<String, StreamSession> _sessions = <String, StreamSession>{};
  final Map<String, StreamSubscription<StreamEvent>> _subs =
      <String, StreamSubscription<StreamEvent>>{};

  void _put(String id, RequestTab Function(RequestTab) f) {
    final list = state.tabs.map((t) => t.id == id ? f(t) : t).toList();
    emit(WorkspaceState(tabs: list, activeId: state.activeId));
  }

  /// Variables for previews, warnings and the resolution inspector.
  ///
  /// With [scoped] the folder and request variables of [tab] are included
  /// (folder secrets read as empty here; sending loads them from the vault).
  VariableResolver resolverFor(RequestTab tab, {bool scoped = true}) {
    final env = _environments.state;
    final folderVars = <Variable>[];
    if (scoped) {
      final parent = _collections.state.node(tab.id)?.parentId;
      for (final f in _collections.state.folderChain(parent)) {
        folderVars.addAll(f.settings.variables);
      }
    }
    return VariableResolver(
      environment: env.active?.variables ?? const <Variable>[],
      collection: _collections.variablesOf(tab.collectionId),
      global: env.globals,
      folder: folderVars,
      request: scoped
          ? RequestExecutor.requestVariables(tab.draft)
          : const <Variable>[],
    );
  }

  /// What [tab] inherits from its collection and folders, secrets loaded.
  Future<EffectiveContext> inheritedFor(RequestTab tab) async {
    final cid = tab.collectionId;
    if (cid == null) return EffectiveContext.none;
    return _collections.effectiveContext(
      collectionId: cid,
      parentId: _collections.state.node(tab.id)?.parentId,
    );
  }

  void newTab({RequestModel? model, RequestKind kind = RequestKind.http}) {
    final m =
        model ??
        RequestModel.blank(method: _settings.state.defaultMethod, kind: kind);
    final tab = RequestTab(draft: m);
    emit(
      WorkspaceState(tabs: <RequestTab>[...state.tabs, tab], activeId: tab.id),
    );
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
    final tab = RequestTab(
      draft: full,
      saved: full,
      collectionId: n.collectionId,
    );
    _collections.touchOpened(n.id);
    emit(
      WorkspaceState(tabs: <RequestTab>[...state.tabs, tab], activeId: tab.id),
    );
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

  void select(String id) =>
      emit(WorkspaceState(tabs: state.tabs, activeId: id));

  /// Selects the next (+1) or previous (-1) tab, wrapping around.
  void selectRelative(int delta) {
    final tabs = state.tabs;
    if (tabs.length < 2) return;
    final i = tabs.indexWhere((t) => t.id == state.activeId);
    final next = ((i < 0 ? 0 : i) + delta) % tabs.length;
    select(tabs[next < 0 ? next + tabs.length : next].id);
  }

  /// Moves a tab. Indexes follow Flutter's ReorderableListView convention:
  /// [newIndex] is the position before the removal when moving right.
  void reorderTabs(int oldIndex, int newIndex) {
    final list = List<RequestTab>.of(state.tabs);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    var target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    target = clampInt(target, 0, list.length - 1);
    if (target == oldIndex) return;
    final tab = list.removeAt(oldIndex);
    list.insert(target, tab);
    emit(WorkspaceState(tabs: list, activeId: state.activeId));
  }

  Future<void> closeTab(String id) async {
    await disconnect(id);
    _tokens.remove(id)?.cancel();
    final rest = state.tabs.where((t) => t.id != id).toList();
    var active = state.activeId;
    if (active == id) {
      final idx = state.tabs.indexWhere((t) => t.id == id);
      active = rest.isEmpty
          ? null
          : rest[clampInt(idx - 1, 0, rest.length - 1)].id;
    }
    emit(WorkspaceState(tabs: rest, activeId: active));
    if (rest.isEmpty) newTab();
  }

  void update(String id, RequestModel draft) =>
      _put(id, (t) => t.copyWith(draft: draft));

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
    newTab(
      model: RequestModel.fromJson(
        tab.draft.toJson(includeSecrets: true),
      ).copyWith(id: RequestModel.blank().id),
    );
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
    final inherited = await inheritedFor(tab);
    final outcome = await _executor.execute(
      tab.draft,
      vars: resolverFor(tab, scoped: false),
      settings: settings,
      cancel: token,
      inherited: inherited,
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
        draft: outcome.updatedAuth == null
            ? t.draft
            : t.draft.copyWith(auth: outcome.updatedAuth),
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
      final inherited = await inheritedFor(tab);
      final req = InheritanceResolver.apply(tab.draft, inherited);
      final resolver = resolverFor(tab, scoped: false).extended(
        folder: inherited.folderVariables,
        request: RequestExecutor.requestVariables(req),
      );
      final built = await _builder.build(req, resolver, _settings.state);
      final StreamSession session = tab.draft.kind == RequestKind.websocket
          ? await WebSocketSession.connect(built.spec)
          : await SseSession.connect(built.spec);
      _sessions[id] = session;
      _subs[id] = session.events.listen(
        (e) {
          _addEvent(id, e);
          if (e.type == StreamEventType.close ||
              e.type == StreamEventType.error) {
            _put(id, (t) => t.copyWith(streaming: false));
          }
        },
        onDone: () {
          _sessions.remove(id);
          _subs.remove(id);
          if (state.tab(id) != null) {
            _put(id, (t) => t.copyWith(streaming: false));
          }
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

  // --- session -----------------------------------------------------------

  @override
  void onChange(Change<WorkspaceState> change) {
    super.onChange(change);
    if (!_restoring) _schedulePersist();
  }

  void _schedulePersist() {
    if (_session == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 600), persistSession);
  }

  /// Writes the open tabs (drafts without secrets) to the session store.
  void persistSession() {
    final store = _session;
    if (store == null) return;
    _persistTimer?.cancel();
    final tabs = state.tabs.take(maxRestoredTabs).toList();
    if (tabs.isEmpty) return;
    final text = jsonEncode(<String, dynamic>{
      'v': 1,
      'active': state.activeId,
      'tabs': <Map<String, dynamic>>[
        for (final t in tabs)
          <String, dynamic>{
            'saved': t.isSaved,
            'collectionId': t.collectionId,
            'draft': t.draft.toJson(),
          },
      ],
    });
    // A pathological session (huge bodies) is not worth persisting.
    if (text.length > 3 * 1024 * 1024) return;
    try {
      store.write(SessionStore.tabsKey, text);
    } on Object catch (e) {
      _log.warn('Could not save the session: ${e.runtimeType}');
    }
  }

  /// Panel sizes of the last session (sidebar width, split fraction and
  /// orientation). Empty when none were saved or restoring is off.
  Map<String, dynamic> readLayout() {
    final raw = _session?.read(SessionStore.layoutKey);
    if (raw == null) return const <String, dynamic>{};
    try {
      return asMap(jsonDecode(raw));
    } on FormatException {
      return const <String, dynamic>{};
    }
  }

  void saveLayout(Map<String, dynamic> layout) {
    try {
      _session?.write(SessionStore.layoutKey, jsonEncode(layout));
    } on Object catch (e) {
      _log.warn('Could not save the layout: ${e.runtimeType}');
    }
  }

  /// Reopens the tabs of the last session. Returns false when there was
  /// nothing to restore. Secrets of unsaved tabs are not restored; saved tabs
  /// get their secrets back from secure storage.
  Future<bool> restoreSession() async {
    final store = _session;
    if (store == null) return false;
    final raw = store.read(SessionStore.tabsKey);
    if (raw == null) return false;
    _restoring = true;
    try {
      final m = asMap(jsonDecode(raw));
      final tabs = <RequestTab>[];
      for (final e in asList(m['tabs']).take(maxRestoredTabs)) {
        final entry = asMap(e);
        final draft = RequestModel.fromJson(entry['draft']);
        final node = entry['saved'] == true
            ? _collections.state.node(draft.id)
            : null;
        if (node != null && !node.isFolder) {
          final full = await _collections.loadFullRequest(node);
          final merged = draft.copyWith(
            auth: draft.auth.withSecrets(full.auth.secretFields()),
          );
          tabs.add(
            RequestTab(
              draft: merged,
              saved: full,
              collectionId: node.collectionId,
            ),
          );
        } else {
          tabs.add(RequestTab(draft: draft));
        }
      }
      if (tabs.isEmpty) return false;
      final active = asString(m['active']);
      emit(
        WorkspaceState(
          tabs: tabs,
          activeId: tabs.any((t) => t.id == active) ? active : tabs.first.id,
        ),
      );
      return true;
    } on FormatException {
      return false;
    } finally {
      _restoring = false;
    }
  }

  @override
  Future<void> close() async {
    persistSession();
    _persistTimer?.cancel();
    for (final t in _tokens.values) {
      t.cancel();
    }
    for (final s in _sessions.values) {
      await s.close();
    }
    return super.close();
  }
}
