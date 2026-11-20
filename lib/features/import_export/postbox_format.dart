import 'dart:convert';

import '../../core/app_info.dart';
import '../../core/util/ids.dart';
import '../../core/util/json_util.dart';
import '../collections/domain/collection_models.dart';
import '../collections/domain/node_settings.dart';
import '../environments/domain/variables.dart';
import '../requests/domain/request_models.dart';
import 'postman.dart';

/// PostBox's own versioned export format.
///
/// ```
/// { "format": "postbox", "version": 1, "exportedAt": "...",
///   "includesSecrets": false, "collections": [...], "environments": [...] }
/// ```
Map<String, dynamic> exportPostBox({
  required List<ImportedCollection> collections,
  List<Environment> environments = const <Environment>[],
  bool includeSecrets = false,
}) {
  List<Map<String, dynamic>> nodes(List<ImportedNode> list) => list.map((n) {
    if (n.isFolder) {
      return <String, dynamic>{
        'type': 'folder',
        'name': n.name,
        'description': n.description,
        if (!n.settings.isEmpty)
          'settings': n.settings.toJson(includeSecrets: includeSecrets),
        'children': nodes(n.children),
      };
    }
    return <String, dynamic>{
      'type': 'request',
      'request': n.request!.toJson(includeSecrets: includeSecrets),
    };
  }).toList();

  return <String, dynamic>{
    'format': 'postbox',
    'version': postboxFormatVersion,
    'app': '$appName $appVersion',
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'includesSecrets': includeSecrets,
    'collections': collections
        .map(
          (c) => <String, dynamic>{
            'name': c.name,
            'description': c.description,
            'variables': c.variables
                .map((v) => v.toJson(includeSecretValue: includeSecrets))
                .toList(),
            if (!c.settings.isEmpty)
              'settings': c.settings.toJson(includeSecrets: includeSecrets),
            'nodes': nodes(c.nodes),
          },
        )
        .toList(),
    'environments': environments
        .map(
          (e) => <String, dynamic>{
            'name': e.name,
            'variables': e.variables
                .map((v) => v.toJson(includeSecretValue: includeSecrets))
                .toList(),
          },
        )
        .toList(),
  };
}

ImportPlan parsePostBox(String text) {
  if (text.length > kMaxImportBytes) {
    return const ImportPlan(
      notes: <ImportNote>[
        ImportNote(NoteLevel.error, 'File is larger than 10 MB.'),
      ],
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    return ImportPlan(
      notes: <ImportNote>[
        ImportNote(NoteLevel.error, 'Invalid JSON: ${e.message}'),
      ],
    );
  }
  if (decoded is! Map || decoded['format'] != 'postbox') {
    return const ImportPlan(
      notes: <ImportNote>[
        ImportNote(
          NoteLevel.error,
          'Not a PostBox export (missing "format": "postbox").',
        ),
      ],
    );
  }
  final version = asInt(decoded['version'], 0);
  if (version < 1 || version > postboxFormatVersion) {
    return ImportPlan(
      notes: <ImportNote>[
        ImportNote(
          NoteLevel.error,
          'Unsupported PostBox format version $version (this app reads up to $postboxFormatVersion).',
        ),
      ],
    );
  }

  var count = 0;
  var skippedScripts = 0;

  /// Imported scripts are never kept: PostBox does not run code that arrived
  /// from a file. Variables get fresh ids so secret storage is not shared.
  NodeSettings cleanSettings(Object? raw) {
    final st = NodeSettings.fromJson(raw);
    if (st.preScript.trim().isNotEmpty) skippedScripts++;
    if (st.postScript.trim().isNotEmpty) skippedScripts++;
    return st.copyWith(
      preScript: '',
      postScript: '',
      variables: st.variables
          .map(
            (v) => Variable(
              id: newId(),
              key: v.key,
              value: v.value,
              secret: v.secret,
              enabled: v.enabled,
            ),
          )
          .toList(),
    );
  }

  List<ImportedNode> nodes(List<dynamic> list, int depth) {
    final out = <ImportedNode>[];
    if (depth > 25) return out;
    for (final raw in list) {
      if (count >= 5000) break;
      final m = asMap(raw);
      if (m['type'] == 'folder') {
        out.add(
          ImportedNode.folder(
            asString(m['name'], 'Folder'),
            nodes(asList(m['children']), depth + 1),
            description: asString(m['description']),
            settings: cleanSettings(m['settings']),
          ),
        );
      } else if (m['type'] == 'request') {
        count++;
        // Fresh ids avoid clashing with existing requests on re-import.
        final r = RequestModel.fromJson(m['request']);
        if (r.preScript.trim().isNotEmpty) skippedScripts++;
        if (r.postScript.trim().isNotEmpty) skippedScripts++;
        out.add(
          ImportedNode.request(
            r.copyWith(id: newId(), preScript: '', postScript: ''),
          ),
        );
      }
    }
    return out;
  }

  Variable freshVar(Object? j) => Variable.fromJson(j).copyWith();

  final collections = asList(decoded['collections']).map((c) {
    final m = asMap(c);
    return ImportedCollection(
      name: asString(m['name'], 'Imported collection'),
      description: asString(m['description']),
      variables: asList(m['variables']).map(freshVar).toList(),
      nodes: nodes(asList(m['nodes']), 0),
      settings: cleanSettings(
        m['settings'],
      ).copyWith(variables: const <Variable>[]),
    );
  }).toList();

  final envs = asList(decoded['environments']).map((e) {
    final m = asMap(e);
    return Environment(
      id: newId(),
      name: asString(m['name'], 'Environment'),
      variables: asList(m['variables']).map(freshVar).toList(),
    );
  }).toList();

  final notes = <ImportNote>[
    if (decoded['includesSecrets'] != true)
      const ImportNote(
        NoteLevel.info,
        'This export contains no secrets. Re-enter secret values after import.',
      ),
  ];
  if (skippedScripts > 0) {
    notes.add(
      ImportNote(
        NoteLevel.warning,
        '$skippedScripts script block(s) were not imported. PostBox never runs scripts that came from a file.',
      ),
    );
  }
  return ImportPlan(collections: collections, environments: envs, notes: notes);
}
