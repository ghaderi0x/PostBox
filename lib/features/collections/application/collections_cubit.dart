import 'package:flutter_bloc/flutter_bloc.dart';

import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';
import '../../secrets/secret_vault.dart';
import '../data/collection_repository.dart';
import '../domain/collection_models.dart';

class CollectionsState {
  const CollectionsState({
    this.collections = const <CollectionRecord>[],
    this.nodes = const <NodeRecord>[],
    this.query = '',
    this.expanded = const <String>{},
  });

  final List<CollectionRecord> collections;
  final List<NodeRecord> nodes;
  final String query;

  /// Ids of expanded collections and folders.
  final Set<String> expanded;

  CollectionsState copyWith({
    List<CollectionRecord>? collections,
    List<NodeRecord>? nodes,
    String? query,
    Set<String>? expanded,
  }) =>
      CollectionsState(
        collections: collections ?? this.collections,
        nodes: nodes ?? this.nodes,
        query: query ?? this.query,
        expanded: expanded ?? this.expanded,
      );

  NodeRecord? node(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  CollectionRecord? collection(String id) {
    for (final c in collections) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<NodeRecord> childrenOf(String collectionId, String? parentId) => nodes
      .where((n) => n.collectionId == collectionId && n.parentId == parentId)
      .toList()
    ..sort((a, b) => a.sort.compareTo(b.sort));

  List<NodeRecord> get favorites =>
      nodes.where((n) => n.favorite && !n.isFolder).toList();

  List<NodeRecord> recents([int limit = 8]) {
    final list = nodes.where((n) => n.lastOpened != null && !n.isFolder).toList()
      ..sort((a, b) => b.lastOpened!.compareTo(a.lastOpened!));
    return list.take(limit).toList();
  }

  /// Case-insensitive match on name, URL and method for request nodes.
  List<NodeRecord> search(String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return const <NodeRecord>[];
    return nodes.where((n) {
      if (n.name.toLowerCase().contains(needle)) return true;
      final r = n.request;
      return r != null &&
          (r.url.toLowerCase().contains(needle) ||
              r.method.toLowerCase().contains(needle));
    }).toList();
  }
}

class CollectionsCubit extends Cubit<CollectionsState> {
  CollectionsCubit(this._repo, this._vault) : super(const CollectionsState());

  final CollectionRepository _repo;
  final SecretVault _vault;

  Future<void> load() async {
    final cols = <CollectionRecord>[];
    for (final c in _repo.listCollections()) {
      cols.add(c.copyWith(variables: await _vault.loadVariables(c.variables)));
    }
    emit(state.copyWith(collections: cols, nodes: _repo.listNodes()));
  }

  void _refreshNodes() => emit(state.copyWith(nodes: _repo.listNodes()));

  void setQuery(String q) => emit(state.copyWith(query: q));

  void toggleExpanded(String id) {
    final s = Set<String>.of(state.expanded);
    if (!s.remove(id)) s.add(id);
    emit(state.copyWith(expanded: s));
  }

  void expand(String id) {
    if (state.expanded.contains(id)) return;
    emit(state.copyWith(expanded: <String>{...state.expanded, id}));
  }

  Future<CollectionRecord> createCollection(String name) async {
    final c = _repo.createCollection(name.trim().isEmpty ? 'Collection' : name.trim());
    emit(state.copyWith(
      collections: <CollectionRecord>[...state.collections, c],
      expanded: <String>{...state.expanded, c.id},
    ));
    return c;
  }

  Future<void> updateCollection(CollectionRecord c) async {
    await _vault.saveVariables(c.variables);
    _repo.updateCollection(c);
    emit(state.copyWith(
      collections: state.collections.map((x) => x.id == c.id ? c : x).toList(),
    ));
  }

  Future<void> deleteCollection(String id) async {
    final c = state.collection(id);
    final removed = _repo.deleteCollection(id);
    for (final rid in removed) {
      await _vault.deleteRequest(rid);
    }
    if (c != null) await _vault.deleteVariables(c.variables);
    emit(state.copyWith(
      collections: state.collections.where((x) => x.id != id).toList(),
      nodes: _repo.listNodes(),
    ));
  }

  Future<NodeRecord> createFolder(String collectionId, String? parentId, String name) async {
    final n = _repo.createFolder(
      collectionId: collectionId,
      parentId: parentId,
      name: name.trim().isEmpty ? 'Folder' : name.trim(),
    );
    _refreshNodes();
    expand(parentId ?? collectionId);
    return n;
  }

  /// Creates the node on first save, updates it afterwards.
  Future<NodeRecord> saveRequest({
    required RequestModel request,
    required String collectionId,
    String? parentId,
  }) async {
    await _vault.saveRequest(request);
    final existing = state.node(request.id);
    final NodeRecord n;
    if (existing == null) {
      n = _repo.createRequest(collectionId: collectionId, parentId: parentId, request: request);
      expand(parentId ?? collectionId);
    } else {
      _repo.saveRequest(request.id, request);
      n = existing;
    }
    _refreshNodes();
    return n;
  }

  Future<RequestModel> loadFullRequest(NodeRecord n) async {
    final r = n.request ?? RequestModel(id: n.id, name: n.name);
    return _vault.loadRequest(r);
  }

  void rename(String id, String name) {
    if (name.trim().isEmpty) return;
    _repo.renameNode(id, name.trim());
    _refreshNodes();
  }

  void setDescription(String id, String d) {
    _repo.setNodeDescription(id, d);
    _refreshNodes();
  }

  void toggleFavorite(String id) {
    final n = state.node(id);
    if (n == null) return;
    _repo.setFavorite(id, !n.favorite);
    _refreshNodes();
  }

  void touchOpened(String id) {
    _repo.touchOpened(id);
    _refreshNodes();
  }

  Future<void> duplicate(String id, {String suffix = ' copy'}) async {
    final map = _repo.duplicateNode(id, nameSuffix: suffix);
    for (final e in map.entries) {
      await _vault.copyRequest(e.key, e.value);
    }
    _refreshNodes();
  }

  Future<void> deleteNode(String id) async {
    final removed = _repo.deleteNode(id);
    for (final rid in removed) {
      await _vault.deleteRequest(rid);
    }
    _refreshNodes();
  }

  /// Moves a node up or down among its siblings.
  void moveBy(String id, int delta) {
    final n = state.node(id);
    if (n == null) return;
    final siblings = state.childrenOf(n.collectionId, n.parentId);
    final i = siblings.indexWhere((s) => s.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return;
    _repo.moveNode(id, collectionId: n.collectionId, newParentId: n.parentId, index: j);
    _refreshNodes();
  }

  void moveTo(String id, {required String collectionId, String? parentId}) {
    _repo.moveNode(id, collectionId: collectionId, newParentId: parentId);
    _refreshNodes();
    expand(parentId ?? collectionId);
  }

  /// Variables of a collection with secret values loaded.
  List<Variable> variablesOf(String? collectionId) =>
      collectionId == null ? const <Variable>[] : (state.collection(collectionId)?.variables ?? const <Variable>[]);

  /// Builds an export tree. With [includeSecrets] request secrets are loaded
  /// from secure storage; otherwise they stay out.
  Future<ImportedCollection> buildExportTree(
    String collectionId, {
    bool includeSecrets = false,
  }) async {
    final c = state.collection(collectionId)!;
    Future<List<ImportedNode>> walk(String? parent) async {
      final out = <ImportedNode>[];
      for (final n in state.childrenOf(collectionId, parent)) {
        if (n.isFolder) {
          out.add(ImportedNode.folder(n.name, await walk(n.id), description: n.description));
        } else {
          var r = n.request ?? RequestModel(id: n.id, name: n.name);
          if (includeSecrets) r = await _vault.loadRequest(r);
          out.add(ImportedNode.request(r));
        }
      }
      return out;
    }

    return ImportedCollection(
      name: c.name,
      description: c.description,
      variables: c.variables,
      nodes: await walk(null),
    );
  }

  /// Commits an import plan atomically. Returns the number of requests added.
  Future<int> commitImport(ImportPlan plan) async {
    final createdRequests = <RequestModel>[];
    final createdVars = <Variable>[];
    _repo.runInTransaction<void>(() {
      for (final ic in plan.collections) {
        final c = _repo.createCollection(ic.name, description: ic.description);
        _repo.updateCollection(c.copyWith(variables: ic.variables));
        createdVars.addAll(ic.variables);
        void add(List<ImportedNode> nodes, String? parent) {
          for (final n in nodes) {
            if (n.isFolder) {
              final f = _repo.createFolder(collectionId: c.id, parentId: parent, name: n.name);
              if (n.description.isNotEmpty) _repo.setNodeDescription(f.id, n.description);
              add(n.children, f.id);
            } else {
              _repo.createRequest(collectionId: c.id, parentId: parent, request: n.request!);
              createdRequests.add(n.request!);
            }
          }
        }

        add(ic.nodes, null);
      }
    });
    for (final r in createdRequests) {
      await _vault.saveRequest(r);
    }
    await _vault.saveVariables(createdVars);
    await load();
    return createdRequests.length;
  }
}
