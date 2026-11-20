import 'dart:convert';

import '../../core/model/key_value.dart';
import '../../core/util/ids.dart';
import '../../core/util/json_util.dart';
import '../collections/domain/collection_models.dart';
import '../environments/domain/variables.dart';
import '../requests/domain/request_models.dart';
import 'postman.dart';

/// Imports OpenAPI 3.x documents in JSON form. YAML is not supported; convert
/// it to JSON first. Only parameters, JSON request bodies and servers[0] are
/// used; security schemes are reported, not applied.
ImportPlan parseOpenApi(String text) {
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
  } on FormatException {
    return const ImportPlan(
      notes: <ImportNote>[
        ImportNote(
          NoteLevel.error,
          'Not valid JSON. YAML OpenAPI files are not supported yet; convert to JSON.',
        ),
      ],
    );
  }
  if (decoded is! Map) {
    return const ImportPlan(
      notes: <ImportNote>[
        ImportNote(NoteLevel.error, 'Expected a JSON object.'),
      ],
    );
  }
  final version = asString(decoded['openapi']);
  if (!version.startsWith('3.')) {
    return ImportPlan(
      notes: <ImportNote>[
        ImportNote(
          NoteLevel.error,
          version.isEmpty
              ? 'Missing "openapi" version (Swagger 2.0 is not supported).'
              : 'Unsupported OpenAPI version $version.',
        ),
      ],
    );
  }
  final root = Map<String, dynamic>.from(decoded);
  final notes = <ImportNote>[];

  Map<String, dynamic> deref(Object? node, [int depth = 0]) {
    final m = asMap(node);
    final ref = m[r'$ref'];
    if (ref is String && ref.startsWith('#/') && depth < 8) {
      Object? cur = root;
      for (final seg in ref.substring(2).split('/')) {
        cur = cur is Map
            ? cur[seg.replaceAll('~1', '/').replaceAll('~0', '~')]
            : null;
      }
      return deref(cur, depth + 1);
    }
    return m;
  }

  Object? example(Object? schemaNode, [int depth = 0]) {
    if (depth > 6) return null;
    final s = deref(schemaNode);
    if (s.containsKey('example')) return s['example'];
    if (s['default'] != null) return s['default'];
    if (s['enum'] is List && (s['enum'] as List).isNotEmpty) {
      return (s['enum'] as List).first;
    }
    switch (asString(s['type'])) {
      case 'object':
        final props = asMap(s['properties']);
        return <String, dynamic>{
          for (final e in props.entries) e.key: example(e.value, depth + 1),
        };
      case 'array':
        return <Object?>[example(s['items'], depth + 1)];
      case 'integer':
      case 'number':
        return 0;
      case 'boolean':
        return false;
      case 'string':
        return 'string';
      default:
        if (s['properties'] != null) {
          return <String, dynamic>{
            for (final e in asMap(s['properties']).entries)
              e.key: example(e.value, depth + 1),
          };
        }
        return null;
    }
  }

  final servers = asList(root['servers']);
  final baseUrl = servers.isNotEmpty
      ? asString(asMap(servers.first)['url'], 'http://localhost')
      : 'http://localhost';
  final vars = <String, Variable>{
    'base_url': Variable(id: newId(), key: 'base_url', value: baseUrl),
  };

  const methods = <String>[
    'get',
    'put',
    'post',
    'delete',
    'options',
    'head',
    'patch',
  ];
  final byTag = <String, List<ImportedNode>>{};
  final untagged = <ImportedNode>[];
  var count = 0;

  final paths = asMap(root['paths']);
  for (final pe in paths.entries) {
    final pathItem = deref(pe.value);
    final commonParams = asList(pathItem['parameters']);
    for (final m in methods) {
      if (pathItem[m] == null) continue;
      if (count >= 5000) break;
      final op = deref(pathItem[m]);
      count++;
      final params = <KeyValue>[];
      final headers = <KeyValue>[];
      for (final raw in <dynamic>[
        ...commonParams,
        ...asList(op['parameters']),
      ]) {
        final p = deref(raw);
        final name = asString(p['name']);
        if (name.isEmpty) continue;
        final isRequired = asBool(p['required'], false);
        final ex = p['example'] ?? example(p['schema']);
        final value = ex == null ? '' : (ex is String ? ex : jsonEncode(ex));
        switch (asString(p['in'])) {
          case 'query':
            params.add(KeyValue(key: name, value: value, enabled: isRequired));
          case 'header':
            headers.add(KeyValue(key: name, value: value, enabled: isRequired));
          case 'path':
            vars.putIfAbsent(
              name,
              () => Variable(
                id: newId(),
                key: name,
                value: value == 'string' ? '' : value,
              ),
            );
        }
      }
      final path = pe.key.replaceAllMapped(
        RegExp(r'\{([^}]+)\}'),
        (mm) => '{{${mm[1]}}}',
      );

      var bodyType = BodyType.none;
      var body = '';
      final rb = deref(op['requestBody']);
      final content = asMap(rb['content']);
      if (content.isNotEmpty) {
        final jsonKey = content.keys.firstWhere(
          (k) => k.toLowerCase().contains('json'),
          orElse: () => '',
        );
        if (jsonKey.isNotEmpty) {
          final media = asMap(content[jsonKey]);
          final ex = media['example'] ?? example(media['schema']);
          bodyType = BodyType.json;
          body = const JsonEncoder.withIndent(
            '  ',
          ).convert(ex ?? <String, dynamic>{});
        } else {
          notes.add(
            ImportNote(
              NoteLevel.info,
              '${m.toUpperCase()} ${pe.key}: only JSON request bodies are generated.',
            ),
          );
        }
      }

      final name = asString(op['summary']).isNotEmpty
          ? asString(op['summary'])
          : (asString(op['operationId']).isNotEmpty
                ? asString(op['operationId'])
                : '${m.toUpperCase()} ${pe.key}');
      final node = ImportedNode.request(
        RequestModel(
          id: newId(),
          name: name,
          method: m.toUpperCase(),
          url: '{{base_url}}$path',
          params: params,
          headers: headers,
          bodyType: bodyType,
          body: body,
          description: asString(op['description']),
        ),
      );
      final tags = asList(op['tags']);
      if (tags.isEmpty || tags.first is! String) {
        untagged.add(node);
      } else {
        byTag
            .putIfAbsent(tags.first as String, () => <ImportedNode>[])
            .add(node);
      }
    }
  }

  final schemes = asMap(asMap(root['components'])['securitySchemes']);
  if (schemes.isNotEmpty) {
    notes.add(
      ImportNote(
        NoteLevel.info,
        'Security schemes (${schemes.keys.join(', ')}) were not applied. Set authentication per request.',
      ),
    );
  }
  if (count == 0) {
    notes.add(
      const ImportNote(NoteLevel.error, 'No operations found under "paths".'),
    );
  }

  final nodes = <ImportedNode>[
    for (final e in byTag.entries) ImportedNode.folder(e.key, e.value),
    ...untagged,
  ];
  final info = asMap(root['info']);
  return ImportPlan(
    collections: <ImportedCollection>[
      ImportedCollection(
        name: asString(info['title'], 'OpenAPI import'),
        description: asString(info['description']),
        variables: vars.values.toList(),
        nodes: nodes,
      ),
    ],
    notes: notes,
  );
}
