import '../../core/model/key_value.dart';
import '../../core/util/ids.dart';
import '../collections/domain/collection_models.dart';
import '../requests/domain/request_models.dart';

/// Splits a shell command into words. Handles single and double quotes,
/// backslash escapes, `$'..'` strings and backslash-newline continuations.
/// Returns null on unterminated quotes. Windows cmd carets are not supported.
List<String>? tokenizeShell(String input) {
  final s = input.replaceAll('\\\r\n', ' ').replaceAll('\\\n', ' ');
  final out = <String>[];
  final cur = StringBuffer();
  var inToken = false;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == "'") {
      final end = s.indexOf("'", i + 1);
      if (end < 0) return null;
      cur.write(s.substring(i + 1, end));
      inToken = true;
      i = end + 1;
    } else if (c == r'$' && i + 1 < s.length && s[i + 1] == "'") {
      i += 2;
      var closed = false;
      while (i < s.length) {
        final d = s[i];
        if (d == '\\' && i + 1 < s.length) {
          final n = s[i + 1];
          switch (n) {
            case 'n':
              cur.write('\n');
            case 't':
              cur.write('\t');
            case 'r':
              cur.write('\r');
            default:
              cur.write(n);
          }
          i += 2;
        } else if (d == "'") {
          closed = true;
          i++;
          break;
        } else {
          cur.write(d);
          i++;
        }
      }
      if (!closed) return null;
      inToken = true;
    } else if (c == '"') {
      i++;
      var closed = false;
      while (i < s.length) {
        final d = s[i];
        if (d == '\\' && i + 1 < s.length && '"\\\$`'.contains(s[i + 1])) {
          cur.write(s[i + 1]);
          i += 2;
        } else if (d == '"') {
          closed = true;
          i++;
          break;
        } else {
          cur.write(d);
          i++;
        }
      }
      if (!closed) return null;
      inToken = true;
    } else if (c == '\\' && i + 1 < s.length) {
      cur.write(s[i + 1]);
      inToken = true;
      i += 2;
    } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      if (inToken) {
        out.add(cur.toString());
        cur.clear();
        inToken = false;
      }
      i++;
    } else {
      cur.write(c);
      inToken = true;
      i++;
    }
  }
  if (inToken) out.add(cur.toString());
  return out;
}

class CurlImport {
  const CurlImport(this.request, this.notes);
  final RequestModel? request;
  final List<ImportNote> notes;
}

const Set<String> _ignoredNoArg = <String>{
  '-s', '--silent', '-S', '--show-error', '-v', '--verbose', '-i', '--include',
  '--compressed', '-f', '--fail', '-O', '-J', '--http1.1', '--http2', '-#',
  '--no-keepalive', '-N', '--no-buffer', '-g', '--globoff', '--path-as-is',
};
const Set<String> _ignoredWithArg = <String>{
  '-o', '--output', '--connect-timeout', '-m', '--max-time', '--retry',
  '-w', '--write-out', '-e', '--referer', '--cacert', '--cert', '--key',
  '-x', '--proxy', '-c', '--cookie-jar', '--limit-rate',
};

CurlImport parseCurl(String command) {
  final notes = <ImportNote>[];
  if (command.length > 256 * 1024) {
    return CurlImport(null, const <ImportNote>[ImportNote(NoteLevel.error, 'Input is too large.')]);
  }
  final tokens = tokenizeShell(command.trim());
  if (tokens == null) {
    return CurlImport(null, const <ImportNote>[ImportNote(NoteLevel.error, 'Unterminated quote.')]);
  }
  if (tokens.isEmpty || tokens.first != 'curl') {
    return CurlImport(null, const <ImportNote>[ImportNote(NoteLevel.error, 'Command must start with "curl".')]);
  }

  String? method;
  String? url;
  final headers = <KeyValue>[];
  final data = <String>[];
  final urlencoded = <String>[];
  final form = <KeyValue>[];
  var basicUser = '';
  var basicPass = '';
  var hasBasic = false;
  var head = false;
  var getMode = false;
  var bearer = '';
  var needsRest = false;

  var i = 1;
  String? next() => i + 1 < tokens.length ? tokens[++i] : null;
  while (i < tokens.length) {
    var t = tokens[i];
    String? inlineValue;
    if (t.startsWith('--') && t.contains('=')) {
      final eq = t.indexOf('=');
      inlineValue = t.substring(eq + 1);
      t = t.substring(0, eq);
    }
    String? arg() => inlineValue ?? next();

    switch (t) {
      case '-X':
      case '--request':
        method = arg()?.toUpperCase();
      case '-H':
      case '--header':
        final h = arg();
        if (h != null) {
          final idx = h.indexOf(':');
          if (idx > 0) {
            final name = h.substring(0, idx).trim();
            final value = h.substring(idx + 1).trim();
            if (name.toLowerCase() == 'authorization' &&
                value.toLowerCase().startsWith('bearer ')) {
              bearer = value.substring(7).trim();
            } else {
              headers.add(KeyValue(key: name, value: value));
            }
          }
        }
      case '-d':
      case '--data':
      case '--data-raw':
      case '--data-binary':
      case '--data-ascii':
        final d = arg();
        if (d != null) {
          if (d.startsWith('@') && t != '--data-raw') {
            notes.add(ImportNote(NoteLevel.warning, 'Body from file "$d" was not read; add the content manually.'));
          } else {
            data.add(d);
          }
        }
      case '--data-urlencode':
        final d = arg();
        if (d != null) urlencoded.add(d);
      case '-F':
      case '--form':
        final f = arg();
        if (f != null) {
          final eq = f.indexOf('=');
          if (eq > 0) {
            final v = f.substring(eq + 1);
            form.add(KeyValue(
              key: f.substring(0, eq),
              value: v.startsWith('@') ? v.substring(1) : v,
              isFile: v.startsWith('@'),
            ));
          }
        }
      case '-u':
      case '--user':
        final u = arg();
        if (u != null) {
          hasBasic = true;
          final idx = u.indexOf(':');
          basicUser = idx < 0 ? u : u.substring(0, idx);
          basicPass = idx < 0 ? '' : u.substring(idx + 1);
        }
      case '-A':
      case '--user-agent':
        final ua = arg();
        if (ua != null) headers.add(KeyValue(key: 'User-Agent', value: ua));
      case '-b':
      case '--cookie':
        final ck = arg();
        if (ck != null) headers.add(KeyValue(key: 'Cookie', value: ck));
      case '-I':
      case '--head':
        head = true;
      case '-G':
      case '--get':
        getMode = true;
      case '--url':
        url = arg();
      case '-k':
      case '--insecure':
        notes.add(const ImportNote(
          NoteLevel.warning,
          'Flag --insecure was ignored. TLS verification stays on; change it in Settings if you really need to.',
        ));
      case '-L':
      case '--location':
        notes.add(const ImportNote(NoteLevel.info, 'Redirects follow the policy in Settings.'));
      default:
        if (_ignoredNoArg.contains(t)) {
          // no effect on the request definition
        } else if (_ignoredWithArg.contains(t)) {
          arg();
          notes.add(ImportNote(NoteLevel.info, 'Option $t was skipped.'));
        } else if (t.startsWith('-') && t.length > 1) {
          notes.add(ImportNote(NoteLevel.warning, 'Unsupported option $t was skipped.'));
          needsRest = true;
        } else if (url == null) {
          url = t;
        }
    }
    i++;
  }
  if (needsRest) {
    notes.add(const ImportNote(NoteLevel.info, 'Check the imported request; skipped options may change behaviour.'));
  }
  if (url == null || url.trim().isEmpty) {
    return CurlImport(null, <ImportNote>[...notes, const ImportNote(NoteLevel.error, 'No URL found.')]);
  }

  var base = url;
  var params = <KeyValue>[];
  final split = splitUrlQuery(url);
  base = split.$1;
  params = List<KeyValue>.of(split.$2);

  final allData = <String>[...data, ...urlencoded];
  if (getMode && allData.isNotEmpty) {
    for (final d in allData) {
      for (final part in d.split('&')) {
        final eq = part.indexOf('=');
        params.add(eq < 0
            ? KeyValue(key: part)
            : KeyValue(key: part.substring(0, eq), value: part.substring(eq + 1)));
      }
    }
    allData.clear();
  }

  final contentType = headers
      .where((h) => h.key.toLowerCase() == 'content-type')
      .map((h) => h.value.toLowerCase())
      .firstOrNull;

  var bodyType = BodyType.none;
  var body = '';
  var formFields = const <KeyValue>[];
  if (form.isNotEmpty) {
    bodyType = BodyType.multipart;
    formFields = form;
    headers.removeWhere((h) => h.key.toLowerCase() == 'content-type');
  } else if (allData.isNotEmpty) {
    final joined = allData.join('&');
    if (contentType != null && contentType.contains('json') ||
        (contentType == null && (joined.trimLeft().startsWith('{') || joined.trimLeft().startsWith('[')))) {
      bodyType = BodyType.json;
      body = data.length == 1 ? data.first : joined;
      headers.removeWhere((h) => h.key.toLowerCase() == 'content-type');
    } else if (contentType == null || contentType.contains('x-www-form-urlencoded')) {
      bodyType = BodyType.formUrlEncoded;
      formFields = joined.split('&').where((p) => p.isNotEmpty).map((p) {
        final eq = p.indexOf('=');
        String dec(String x) {
          try {
            return Uri.decodeQueryComponent(x);
          } on ArgumentError {
            return x;
          }
        }

        return eq < 0
            ? KeyValue(key: dec(p))
            : KeyValue(key: dec(p.substring(0, eq)), value: dec(p.substring(eq + 1)));
      }).toList();
      headers.removeWhere((h) => h.key.toLowerCase() == 'content-type');
    } else {
      bodyType = BodyType.raw;
      body = joined;
      final ct = headers.firstWhere((h) => h.key.toLowerCase() == 'content-type');
      headers.remove(ct);
    }
  }

  final resolvedMethod = head
      ? 'HEAD'
      : (method ?? ((bodyType != BodyType.none) ? 'POST' : 'GET'));

  var auth = const AuthConfig();
  if (bearer.isNotEmpty) {
    auth = AuthConfig(type: AuthType.bearer, token: bearer);
  } else if (hasBasic) {
    auth = AuthConfig(type: AuthType.basic, username: basicUser, password: basicPass);
  }

  final req = RequestModel(
    id: newId(),
    name: '',
    method: resolvedMethod,
    url: base,
    params: params,
    headers: headers,
    bodyType: bodyType,
    body: body,
    bodyAux: bodyType == BodyType.raw
        ? (contentType ?? '')
        : '',
    formFields: formFields,
    auth: auth,
  );
  return CurlImport(req, notes);
}

String _shq(String s) => "'${s.replaceAll("'", "'\\''")}'";

/// Exports a request as a cURL command. Variables stay as `{{name}}`.
/// Secrets are replaced by placeholders unless [includeSecrets] is true.
String exportCurl(RequestModel r, {bool includeSecrets = false}) {
  final parts = <String>['curl'];
  final method = r.method.toUpperCase();
  if (method != 'GET') parts.add('-X ${_shq(method)}');

  final query = r.params
      .where((p) => p.enabled && p.key.isNotEmpty)
      .map((p) => '${Uri.encodeQueryComponent(p.key)}=${Uri.encodeQueryComponent(p.value)}')
      .toList();

  final a = r.auth;
  if (a.type == AuthType.apiKey && !a.apiKeyInHeader && a.apiKeyName.isNotEmpty) {
    query.add(
      '${Uri.encodeQueryComponent(a.apiKeyName)}=${Uri.encodeQueryComponent(includeSecrets ? a.apiKeyValue : '<api-key>')}',
    );
  }
  var url = r.url;
  if (query.isNotEmpty) url += (url.contains('?') ? '&' : '?') + query.join('&');
  parts.add(_shq(url));

  for (final h in r.headers.where((h) => h.enabled && h.key.isNotEmpty)) {
    parts.add('-H ${_shq('${h.key}: ${h.value}')}');
  }
  switch (a.type) {
    case AuthType.basic:
      parts.add('-u ${_shq('${a.username}:${includeSecrets ? a.password : '<password>'}')}');
    case AuthType.bearer:
      parts.add('-H ${_shq('Authorization: Bearer ${includeSecrets ? a.token : '<token>'}')}');
    case AuthType.oauth2:
      parts.add('-H ${_shq('Authorization: Bearer ${includeSecrets ? a.accessToken : '<access-token>'}')}');
    case AuthType.apiKey:
      if (a.apiKeyInHeader && a.apiKeyName.isNotEmpty) {
        parts.add('-H ${_shq('${a.apiKeyName}: ${includeSecrets ? a.apiKeyValue : '<api-key>'}')}');
      }
    case AuthType.none:
      break;
  }

  switch (r.bodyType) {
    case BodyType.none:
      break;
    case BodyType.json:
      parts.add("-H 'Content-Type: application/json'");
      parts.add('--data-raw ${_shq(r.body)}');
    case BodyType.text:
      parts.add("-H 'Content-Type: text/plain'");
      parts.add('--data-raw ${_shq(r.body)}');
    case BodyType.raw:
      if (r.bodyAux.isNotEmpty) parts.add('-H ${_shq('Content-Type: ${r.bodyAux}')}');
      parts.add('--data-raw ${_shq(r.body)}');
    case BodyType.formUrlEncoded:
      for (final f in r.formFields.where((f) => f.enabled && f.key.isNotEmpty)) {
        parts.add('--data-urlencode ${_shq('${f.key}=${f.value}')}');
      }
    case BodyType.multipart:
      for (final f in r.formFields.where((f) => f.enabled && f.key.isNotEmpty)) {
        parts.add('-F ${_shq('${f.key}=${f.isFile ? '@' : ''}${f.value}')}');
      }
    case BodyType.graphql:
      final vars = r.bodyAux.trim();
      final payload = vars.isEmpty
          ? '{"query":${_jsonString(r.body)}}'
          : '{"query":${_jsonString(r.body)},"variables":$vars}';
      parts.add("-H 'Content-Type: application/json'");
      parts.add('--data-raw ${_shq(payload)}');
  }
  return parts.join(' \\\n  ');
}

String _jsonString(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    switch (r) {
      case 0x22:
        b.write('\\"');
      case 0x5C:
        b.write('\\\\');
      case 0x0A:
        b.write('\\n');
      case 0x0D:
        b.write('\\r');
      case 0x09:
        b.write('\\t');
      default:
        if (r < 0x20) {
          b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(r);
        }
    }
  }
  b.write('"');
  return b.toString();
}
