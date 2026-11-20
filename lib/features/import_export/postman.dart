import 'dart:convert';

import '../../core/model/key_value.dart';
import '../../core/util/ids.dart';
import '../../core/util/json_util.dart';
import '../collections/domain/collection_models.dart';
import '../collections/domain/node_settings.dart';
import '../environments/domain/variables.dart';
import '../requests/domain/request_models.dart';

const int kMaxImportBytes = 10 * 1024 * 1024;
const int _maxDepth = 25;
const int _maxRequests = 5000;

/// Parses a Postman Collection v2.1 (v2.0 with a warning). Never executes
/// scripts; they are counted and reported as skipped.
ImportPlan parsePostmanCollection(String text) {
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
  if (decoded is! Map) {
    return const ImportPlan(
      notes: <ImportNote>[
        ImportNote(NoteLevel.error, 'Expected a JSON object.'),
      ],
    );
  }
  final info = asMap(decoded['info']);
  final schema = asString(info['schema']);
  if (info.isEmpty || decoded['item'] is! List) {
    return const ImportPlan(
      notes: <ImportNote>[
        ImportNote(
          NoteLevel.error,
          'Not a Postman collection (missing "info" or "item").',
        ),
      ],
    );
  }
  final notes = <ImportNote>[];
  if (!schema.contains('v2.1')) {
    if (schema.contains('v2.0')) {
      notes.add(
        const ImportNote(
          NoteLevel.warning,
          'Collection is v2.0; importing as v2.1 may lose details.',
        ),
      );
    } else {
      return ImportPlan(
        notes: <ImportNote>[
          ImportNote(
            NoteLevel.error,
            'Unsupported collection schema: ${schema.isEmpty ? 'unknown' : schema}',
          ),
        ],
      );
    }
  }

  var scripts = 0;
  var requests = 0;
  var unsupportedAuth = 0;
  var unsupportedBody = 0;

  /// Auth block of a collection, folder or request. Null when empty or
  /// unsupported (counted in [unsupportedAuth]).
  AuthConfig? parseAuth(Map<String, dynamic> a) {
    String pick(String group, String key) {
      for (final e in asList(a[group])) {
        final m = asMap(e);
        if (asString(m['key']) == key) return asString(m['value']);
      }
      return '';
    }

    switch (asString(a['type'])) {
      case 'bearer':
        return AuthConfig(
          type: AuthType.bearer,
          token: pick('bearer', 'token'),
        );
      case 'basic':
        return AuthConfig(
          type: AuthType.basic,
          username: pick('basic', 'username'),
          password: pick('basic', 'password'),
        );
      case 'apikey':
        return AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: pick('apikey', 'key'),
          apiKeyValue: pick('apikey', 'value'),
          apiKeyInHeader: pick('apikey', 'in') != 'query',
        );
      case '':
        return null;
      case 'noauth':
        return const AuthConfig();
      default:
        unsupportedAuth++;
        return null;
    }
  }

  List<Variable> parseVars(Object? raw) => asList(raw)
      .map((v) {
        final m = asMap(v);
        return Variable(
          id: newId(),
          key: asString(m['key']),
          value: asString(m['value']),
          enabled: !asBool(m['disabled'], false),
        );
      })
      .where((v) => v.key.isNotEmpty)
      .toList();

  RequestModel? parseRequest(Map<String, dynamic> item, bool inheritAuth) {
    final reqRaw = item['request'];
    final Map<String, dynamic> req;
    if (reqRaw is String) {
      req = <String, dynamic>{'url': reqRaw};
    } else {
      req = asMap(reqRaw);
    }
    if (item['event'] is List && (item['event'] as List).isNotEmpty) scripts++;

    final urlRaw = req['url'];
    var rawUrl = '';
    List<KeyValue>? queryFromArray;
    if (urlRaw is String) {
      rawUrl = urlRaw;
    } else if (urlRaw is Map) {
      rawUrl = asString(urlRaw['raw']);
      if (urlRaw['query'] is List) {
        queryFromArray = asList(urlRaw['query']).map((q) {
          final m = asMap(q);
          return KeyValue(
            key: asString(m['key']),
            value: asString(m['value']),
            enabled: !asBool(m['disabled'], false),
          );
        }).toList();
      }
    }
    final split = splitUrlQuery(rawUrl);
    final params = queryFromArray ?? split.$2;

    final headers = asList(req['header']).map((h) {
      final m = asMap(h);
      return KeyValue(
        key: asString(m['key']),
        value: asString(m['value']),
        enabled: !asBool(m['disabled'], false),
      );
    }).toList();

    var bodyType = BodyType.none;
    var body = '';
    var aux = '';
    var form = <KeyValue>[];
    final b = asMap(req['body']);
    switch (asString(b['mode'])) {
      case 'raw':
        body = asString(b['raw']);
        final lang = asString(asMap(asMap(b['options'])['raw'])['language']);
        bodyType = lang == 'json' ? BodyType.json : BodyType.text;
      case 'urlencoded':
        bodyType = BodyType.formUrlEncoded;
        form = asList(b['urlencoded']).map((f) {
          final m = asMap(f);
          return KeyValue(
            key: asString(m['key']),
            value: asString(m['value']),
            enabled: !asBool(m['disabled'], false),
          );
        }).toList();
      case 'formdata':
        bodyType = BodyType.multipart;
        form = asList(b['formdata']).map((f) {
          final m = asMap(f);
          final isFile = asString(m['type']) == 'file';
          return KeyValue(
            key: asString(m['key']),
            value: isFile ? asString(m['src']) : asString(m['value']),
            enabled: !asBool(m['disabled'], false),
            isFile: isFile,
          );
        }).toList();
      case 'graphql':
        bodyType = BodyType.graphql;
        final g = asMap(b['graphql']);
        body = asString(g['query']);
        aux = asString(g['variables']);
      case '':
        break;
      default:
        unsupportedBody++;
    }

    final AuthConfig auth;
    if (req.containsKey('auth')) {
      auth = parseAuth(asMap(req['auth'])) ?? const AuthConfig();
    } else {
      // Postman: a request without its own auth uses the one above it.
      auth = inheritAuth
          ? const AuthConfig(type: AuthType.inherit)
          : const AuthConfig();
    }

    requests++;
    return RequestModel(
      id: newId(),
      name: asString(item['name']),
      method: asString(req['method'], 'GET').toUpperCase(),
      url: split.$1,
      params: params,
      headers: headers,
      bodyType: bodyType,
      body: body,
      bodyAux: aux,
      formFields: form,
      auth: auth,
      description: req['description'] is String
          ? req['description'] as String
          : '',
    );
  }

  List<ImportedNode> walk(List<dynamic> items, int depth, bool inheritAuth) {
    final out = <ImportedNode>[];
    if (depth > _maxDepth) {
      notes.add(
        const ImportNote(
          NoteLevel.warning,
          'Folders nested deeper than 25 levels were skipped.',
        ),
      );
      return out;
    }
    for (final raw in items) {
      if (requests >= _maxRequests) {
        notes.add(
          const ImportNote(
            NoteLevel.warning,
            'Import stopped after 5000 requests.',
          ),
        );
        break;
      }
      final item = asMap(raw);
      if (item['item'] is List) {
        if (item['event'] is List && (item['event'] as List).isNotEmpty) {
          scripts++;
        }
        final folderAuth = item['auth'] is Map
            ? parseAuth(asMap(item['auth']))
            : null;
        final folderVars = parseVars(item['variable']);
        out.add(
          ImportedNode.folder(
            asString(item['name'], 'Folder'),
            walk(
              asList(item['item']),
              depth + 1,
              inheritAuth || folderAuth != null,
            ),
            description: item['description'] is String
                ? item['description'] as String
                : '',
            settings: NodeSettings(
              auth: folderAuth ?? const AuthConfig(type: AuthType.inherit),
              variables: folderVars,
            ),
          ),
        );
      } else if (item['request'] != null) {
        final r = parseRequest(item, inheritAuth);
        if (r != null) out.add(ImportedNode.request(r));
      }
    }
    return out;
  }

  final collectionAuth = decoded['auth'] is Map
      ? parseAuth(asMap(decoded['auth']))
      : null;
  final nodes = walk(asList(decoded['item']), 0, collectionAuth != null);
  if ((decoded['event'] is List) && (decoded['event'] as List).isNotEmpty) {
    scripts++;
  }
  final vars = parseVars(decoded['variable']);

  if (scripts > 0) {
    notes.add(
      ImportNote(
        NoteLevel.warning,
        '$scripts script block(s) were not imported. PostBox never runs imported scripts.',
      ),
    );
  }
  if (unsupportedAuth > 0) {
    notes.add(
      ImportNote(
        NoteLevel.warning,
        '$unsupportedAuth request(s) use an unsupported auth type and were imported without auth.',
      ),
    );
  }
  if (unsupportedBody > 0) {
    notes.add(
      ImportNote(
        NoteLevel.warning,
        '$unsupportedBody request(s) use an unsupported body mode and were imported without a body.',
      ),
    );
  }
  if (vars.any(
    (v) =>
        v.key.toLowerCase().contains('token') ||
        v.key.toLowerCase().contains('secret') ||
        v.key.toLowerCase().contains('password'),
  )) {
    notes.add(
      const ImportNote(
        NoteLevel.info,
        'Some variables look like secrets. Mark them as secret after import.',
      ),
    );
  }

  return ImportPlan(
    collections: <ImportedCollection>[
      ImportedCollection(
        name: asString(info['name'], 'Imported collection'),
        description: info['description'] is String
            ? info['description'] as String
            : '',
        variables: vars,
        nodes: nodes,
        settings: NodeSettings(
          auth: collectionAuth ?? const AuthConfig(type: AuthType.inherit),
        ),
      ),
    ],
    notes: notes,
  );
}

/// Exports one collection as Postman v2.1. Lossy: assertions, extractions and
/// OAuth 2.0 settings have no equivalent and are dropped (documented in
/// docs/IMPORT_EXPORT.md). Secrets are blanked unless [includeSecrets].
Map<String, dynamic> exportPostmanCollection(
  ImportedCollection c, {
  bool includeSecrets = false,
}) {
  Map<String, dynamic> kv(KeyValue k) => <String, dynamic>{
    'key': k.key,
    'value': k.value,
    if (!k.enabled) 'disabled': true,
  };

  Map<String, dynamic>? authJson(AuthConfig a) {
    String s(String v) => includeSecrets ? v : '';
    Map<String, dynamic>? auth;
    switch (a.type) {
      case AuthType.bearer:
        auth = <String, dynamic>{
          'type': 'bearer',
          'bearer': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': 'token',
              'value': s(a.token),
              'type': 'string',
            },
          ],
        };
      case AuthType.basic:
        auth = <String, dynamic>{
          'type': 'basic',
          'basic': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': 'username',
              'value': a.username,
              'type': 'string',
            },
            <String, dynamic>{
              'key': 'password',
              'value': s(a.password),
              'type': 'string',
            },
          ],
        };
      case AuthType.apiKey:
        auth = <String, dynamic>{
          'type': 'apikey',
          'apikey': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': 'key',
              'value': a.apiKeyName,
              'type': 'string',
            },
            <String, dynamic>{
              'key': 'value',
              'value': s(a.apiKeyValue),
              'type': 'string',
            },
            <String, dynamic>{
              'key': 'in',
              'value': a.apiKeyInHeader ? 'header' : 'query',
              'type': 'string',
            },
          ],
        };
      case AuthType.oauth2:
      case AuthType.none:
      case AuthType.inherit:
        break;
    }
    return auth;
  }

  Map<String, dynamic> request(RequestModel r) {
    final query = r.params.where((p) => p.key.isNotEmpty).toList();
    final rawQuery = query
        .where((p) => p.enabled)
        .map((p) => '${p.key}=${p.value}')
        .join('&');
    final raw = rawQuery.isEmpty ? r.url : '${r.url}?$rawQuery';
    final body = <String, dynamic>{};
    switch (r.bodyType) {
      case BodyType.none:
        break;
      case BodyType.json:
        body['mode'] = 'raw';
        body['raw'] = r.body;
        body['options'] = <String, dynamic>{
          'raw': <String, dynamic>{'language': 'json'},
        };
      case BodyType.text:
      case BodyType.raw:
        body['mode'] = 'raw';
        body['raw'] = r.body;
      case BodyType.formUrlEncoded:
        body['mode'] = 'urlencoded';
        body['urlencoded'] = r.formFields.map(kv).toList();
      case BodyType.multipart:
        body['mode'] = 'formdata';
        body['formdata'] = r.formFields
            .map(
              (f) => <String, dynamic>{
                'key': f.key,
                'type': f.isFile ? 'file' : 'text',
                if (f.isFile) 'src': f.value else 'value': f.value,
                if (!f.enabled) 'disabled': true,
              },
            )
            .toList();
      case BodyType.binary:
        body['mode'] = 'file';
        body['file'] = <String, dynamic>{'src': r.body};
      case BodyType.graphql:
        body['mode'] = 'graphql';
        body['graphql'] = <String, dynamic>{
          'query': r.body,
          'variables': r.bodyAux,
        };
    }
    final auth = authJson(r.auth);
    return <String, dynamic>{
      'method': r.method,
      'header': r.headers.map(kv).toList(),
      if (body.isNotEmpty) 'body': body,
      'url': <String, dynamic>{'raw': raw, 'query': query.map(kv).toList()},
      'auth': ?auth,
      if (r.description.isNotEmpty) 'description': r.description,
    };
  }

  List<Map<String, dynamic>> items(List<ImportedNode> nodes) => nodes.map((n) {
    if (n.isFolder) {
      final folderAuth = n.settings.auth.type == AuthType.inherit
          ? null
          : authJson(n.settings.auth);
      return <String, dynamic>{
        'name': n.name,
        if (n.description.isNotEmpty) 'description': n.description,
        'auth': ?folderAuth,
        if (n.settings.variables.isNotEmpty)
          'variable': n.settings.variables
              .map(
                (v) => <String, dynamic>{
                  'key': v.key,
                  'value': v.secret && !includeSecrets ? '' : v.value,
                },
              )
              .toList(),
        'item': items(n.children),
      };
    }
    final r = n.request!;
    return <String, dynamic>{'name': r.displayName, 'request': request(r)};
  }).toList();

  return <String, dynamic>{
    'info': <String, dynamic>{
      '_postman_id': newId(),
      'name': c.name,
      if (c.description.isNotEmpty) 'description': c.description,
      'schema':
          'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    },
    if (c.settings.auth.type != AuthType.inherit &&
        authJson(c.settings.auth) != null)
      'auth': authJson(c.settings.auth),
    'item': items(c.nodes),
    'variable': c.variables
        .map(
          (v) => <String, dynamic>{
            'key': v.key,
            'value': v.secret && !includeSecrets ? '' : v.value,
          },
        )
        .toList(),
  };
}

String prettyJson(Object? v) => const JsonEncoder.withIndent('  ').convert(v);
