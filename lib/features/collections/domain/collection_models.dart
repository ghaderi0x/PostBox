import '../../environments/domain/variables.dart';
import '../../requests/domain/request_models.dart';
import 'node_settings.dart';

enum NodeKind { folder, request }

class CollectionRecord {
  const CollectionRecord({
    required this.id,
    required this.name,
    this.description = '',
    this.sort = 0,
    this.variables = const <Variable>[],
    this.settings = NodeSettings.empty,
  });

  final String id;
  final String name;
  final String description;
  final int sort;
  final List<Variable> variables;

  /// Auth, headers and scripts inherited by every request in the collection.
  /// (Collection variables stay in [variables].)
  final NodeSettings settings;

  CollectionRecord copyWith({
    String? name,
    String? description,
    int? sort,
    List<Variable>? variables,
    NodeSettings? settings,
  }) => CollectionRecord(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    sort: sort ?? this.sort,
    variables: variables ?? this.variables,
    settings: settings ?? this.settings,
  );
}

class NodeRecord {
  const NodeRecord({
    required this.id,
    required this.collectionId,
    required this.parentId,
    required this.kind,
    required this.name,
    this.description = '',
    this.sort = 0,
    this.favorite = false,
    this.lastOpened,
    this.request,
    this.settings = NodeSettings.empty,
  });

  final String id;
  final String collectionId;
  final String? parentId;
  final NodeKind kind;
  final String name;
  final String description;
  final int sort;
  final bool favorite;

  /// Epoch milliseconds, null if never opened.
  final int? lastOpened;

  /// Set for request nodes. Secrets are not included; use SecretVault.
  final RequestModel? request;

  /// Folder settings (empty for requests).
  final NodeSettings settings;

  bool get isFolder => kind == NodeKind.folder;
}

/// Tree shape produced by importers, committed by the collections cubit.
class ImportedNode {
  const ImportedNode.folder(
    this.name,
    this.children, {
    this.description = '',
    this.settings = NodeSettings.empty,
  }) : request = null;
  const ImportedNode.request(RequestModel this.request)
    : name = '',
      children = const <ImportedNode>[],
      description = '',
      settings = NodeSettings.empty;

  final String name;
  final String description;
  final List<ImportedNode> children;
  final RequestModel? request;
  final NodeSettings settings;

  bool get isFolder => request == null;

  int countRequests() =>
      isFolder ? children.fold<int>(0, (a, c) => a + c.countRequests()) : 1;
}

class ImportedCollection {
  const ImportedCollection({
    required this.name,
    this.description = '',
    this.variables = const <Variable>[],
    this.nodes = const <ImportedNode>[],
    this.settings = NodeSettings.empty,
  });

  final String name;
  final String description;
  final List<Variable> variables;
  final NodeSettings settings;
  final List<ImportedNode> nodes;

  int get requestCount => nodes.fold<int>(0, (a, n) => a + n.countRequests());
}

enum NoteLevel { info, warning, error }

class ImportNote {
  const ImportNote(this.level, this.message);
  final NoteLevel level;
  final String message;
}

class ImportPlan {
  const ImportPlan({
    this.collections = const <ImportedCollection>[],
    this.environments = const <Environment>[],
    this.notes = const <ImportNote>[],
  });

  final List<ImportedCollection> collections;
  final List<Environment> environments;
  final List<ImportNote> notes;

  bool get hasErrors => notes.any((n) => n.level == NoteLevel.error);
  int get requestCount =>
      collections.fold<int>(0, (a, c) => a + c.requestCount);
}
