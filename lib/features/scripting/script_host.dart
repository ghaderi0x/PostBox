import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/model/key_value.dart';
import '../../core/util/ids.dart';
import '../environments/domain/variables.dart';
import '../http/domain/http_engine.dart';
import '../requests/domain/request_models.dart';
import 'script_interpreter.dart';
import 'script_parser.dart';

class ScriptTestResult {
  const ScriptTestResult(this.name, this.passed);
  final String name;
  final bool passed;
}

class ScriptRunResult {
  const ScriptRunResult({
    this.logs = const <String>[],
    this.tests = const <ScriptTestResult>[],
    this.variableWrites = const <String, String>{},
    this.error,
    this.steps = 0,
  });

  static const ScriptRunResult empty = ScriptRunResult();

  final List<String> logs;
  final List<ScriptTestResult> tests;

  /// Values set with `vars.set`. They are never secret. The workspace saves
  /// them like extracted values (active environment, or globals); the runner
  /// keeps them in memory for one iteration.
  final Map<String, String> variableWrites;

  /// Set when a script failed to parse or run; the message includes the line.
  final String? error;
  final int steps;

  bool get hasContent => logs.isNotEmpty || tests.isNotEmpty || error != null;
}

String _s(Object? v) => ScriptInterpreter.display(v);

/// `vars.get/set/has`. Secret variables are invisible to scripts.
class _VarsHost extends HostObject {
  _VarsHost(this._resolver, this.writes);

  final VariableResolver _resolver;
  final Map<String, String> writes;

  String? _lookup(String name) {
    final w = writes[name];
    if (w != null) return w;
    if (!_resolver.names.contains(name)) return null;
    if (_resolver.isSecret(name)) return null;
    return _resolver.displayValue(name);
  }

  @override
  Object? getProperty(String name) => _lookup(name);

  @override
  void setProperty(String name, Object? value) =>
      callMethod('set', <Object?>[name, value]);

  @override
  Object? callMethod(String name, List<Object?> args) {
    final key = args.isEmpty ? '' : _s(args[0]);
    switch (name) {
      case 'get':
        return _lookup(key);
      case 'has':
        return _lookup(key) != null;
      case 'set':
        if (key.isEmpty || key.length > 200) {
          throw const ScriptException(
            'vars.set needs a name up to 200 characters.',
          );
        }
        if (writes.length >= 200 && !writes.containsKey(key)) {
          throw const ScriptException('Too many variables set by scripts.');
        }
        final v = args.length > 1 ? _s(args[1]) : '';
        if (v.length > 100000) {
          throw const ScriptException('Variable value is too long.');
        }
        writes[key] = v;
        return null;
    }
    throw ScriptException('vars has no method "$name".');
  }
}

class _HeadersHost extends HostObject {
  _HeadersHost(this.list, {this.readOnly = false});

  final List<KeyValue> list;
  final bool readOnly;

  int _find(String name) => list.indexWhere(
    (h) => h.enabled && h.key.toLowerCase() == name.toLowerCase(),
  );

  @override
  Object? getProperty(String name) {
    final i = _find(name);
    return i < 0 ? null : list[i].value;
  }

  @override
  void setProperty(String name, Object? value) {
    if (readOnly) {
      throw const ScriptException('Response headers are read-only.');
    }
    final i = _find(name);
    final kv = KeyValue(key: name, value: _s(value));
    if (i < 0) {
      list.add(kv);
    } else {
      list[i] = kv;
    }
  }

  @override
  Object? callMethod(String name, List<Object?> args) {
    final key = args.isEmpty ? '' : _s(args[0]);
    switch (name) {
      case 'get':
        return getProperty(key);
      case 'has':
        return _find(key) >= 0;
      case 'set':
        setProperty(key, args.length > 1 ? args[1] : '');
        return null;
      case 'remove':
        if (readOnly) {
          throw const ScriptException('Response headers are read-only.');
        }
        list.removeWhere((h) => h.key.toLowerCase() == key.toLowerCase());
        return null;
    }
    throw ScriptException('headers has no method "$name".');
  }
}

class _RequestHost extends HostObject {
  _RequestHost(RequestModel r)
    : method = r.method,
      url = r.url,
      body = r.body,
      _bodyType = r.bodyType,
      headers = List<KeyValue>.of(r.headers);

  String method;
  String url;
  String body;
  final BodyType _bodyType;
  final List<KeyValue> headers;

  bool get _textBody =>
      _bodyType == BodyType.json ||
      _bodyType == BodyType.text ||
      _bodyType == BodyType.raw ||
      _bodyType == BodyType.graphql;

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'method':
        return method;
      case 'url':
        return url;
      case 'body':
        return body;
      case 'headers':
        return _HeadersHost(headers);
    }
    return null;
  }

  @override
  void setProperty(String name, Object? value) {
    switch (name) {
      case 'method':
        method = _s(value).toUpperCase();
      case 'url':
        url = _s(value);
      case 'body':
        if (!_textBody) {
          throw const ScriptException(
            'request.body can only be set for JSON, text, raw and GraphQL bodies.',
          );
        }
        body = _s(value);
      default:
        throw ScriptException('request.$name is read-only.');
    }
  }

  @override
  Object? callMethod(String name, List<Object?> args) =>
      throw ScriptException('request has no method "$name".');
}

class _ResponseHost extends HostObject {
  _ResponseHost(this._r);

  final HttpResult _r;
  String? _text;
  Object? _json;
  bool _jsonDone = false;

  String get _bodyText => _text ??= utf8.decode(_r.body, allowMalformed: true);

  Object? _parsed() {
    if (!_jsonDone) {
      _jsonDone = true;
      try {
        _json = jsonDecode(_bodyText);
      } on FormatException {
        throw const ScriptException('The response body is not valid JSON.');
      }
    }
    return _json;
  }

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'status':
        return _r.statusCode;
      case 'reason':
        return _r.reasonPhrase;
      case 'time':
        return _r.duration.inMilliseconds;
      case 'size':
        return _r.body.length;
      case 'url':
        return _r.finalUrl.toString();
      case 'body':
        return _bodyText;
      case 'headers':
        return _HeadersHost(<KeyValue>[
          for (final e in _r.headers.entries)
            KeyValue(key: e.key, value: e.value.join(', ')),
        ], readOnly: true);
    }
    return null;
  }

  @override
  Object? callMethod(String name, List<Object?> args) {
    switch (name) {
      case 'json':
        return _parsed();
      case 'text':
        return _bodyText;
      case 'header':
        return _r.header(args.isEmpty ? '' : _s(args[0]));
    }
    throw ScriptException('response has no method "$name".');
  }
}

/// Runs scripts. Scripts cannot read secrets, files or the network; they can
/// change the outgoing request (pre-request only), set runtime variables and
/// report test results.
class ScriptRunner {
  const ScriptRunner({this.limits = const ScriptLimits()});

  final ScriptLimits limits;

  static const int _maxLogLines = 200;

  /// Runs [scripts] in order before the request is sent. The returned request
  /// carries any changes the scripts made.
  (RequestModel, ScriptRunResult) runPre({
    required List<String> scripts,
    required RequestModel request,
    required VariableResolver vars,
  }) {
    final active = scripts.where((s) => s.trim().isNotEmpty).toList();
    if (active.isEmpty) return (request, ScriptRunResult.empty);

    final host = _RequestHost(request);
    final writes = <String, String>{};
    final logs = <String>[];
    final tests = <ScriptTestResult>[];
    var steps = 0;
    String? error;
    for (final src in active) {
      final r = _runOne(
        src,
        <String, Object?>{'request': host, 'vars': _VarsHost(vars, writes)},
        logs,
        tests,
      );
      steps += r.$1;
      if (r.$2 != null) {
        error = r.$2;
        break;
      }
    }
    final changed = request.copyWith(
      method: host.method,
      url: host.url,
      body: host.body,
      headers: host.headers,
    );
    return (
      changed,
      ScriptRunResult(
        logs: logs,
        tests: tests,
        variableWrites: writes,
        error: error,
        steps: steps,
      ),
    );
  }

  /// Runs [scripts] after the response arrived. The request is read-only here.
  ScriptRunResult runPost({
    required List<String> scripts,
    required RequestModel request,
    required VariableResolver vars,
    required HttpResult response,
    Map<String, String> earlierWrites = const <String, String>{},
  }) {
    final active = scripts.where((s) => s.trim().isNotEmpty).toList();
    if (active.isEmpty) return ScriptRunResult.empty;

    final writes = <String, String>{...earlierWrites};
    final logs = <String>[];
    final tests = <ScriptTestResult>[];
    final resp = _ResponseHost(response);
    var steps = 0;
    String? error;
    for (final src in active) {
      final r = _runOne(
        src,
        <String, Object?>{
          'request': _ReadOnlyRequest(request),
          'response': resp,
          'vars': _VarsHost(vars, writes),
        },
        logs,
        tests,
      );
      steps += r.$1;
      if (r.$2 != null) {
        error = r.$2;
        break;
      }
    }
    return ScriptRunResult(
      logs: logs,
      tests: tests,
      variableWrites: <String, String>{
        for (final e in writes.entries)
          if (earlierWrites[e.key] != e.value) e.key: e.value,
      },
      error: error,
      steps: steps,
    );
  }

  (int, String?) _runOne(
    String src,
    Map<String, Object?> globals,
    List<String> logs,
    List<ScriptTestResult> tests,
  ) {
    final functions = <String, ScriptFunction>{
      'log': (a) {
        if (logs.length < _maxLogLines) {
          final line = a.map(_s).join(' ');
          logs.add(line.length > 2000 ? '${line.substring(0, 2000)}…' : line);
        }
        return null;
      },
      'test': (a) {
        if (tests.length < 200) {
          tests.add(
            ScriptTestResult(
              a.isEmpty ? 'test' : _s(a[0]),
              a.length > 1 && _truthy(a[1]),
            ),
          );
        }
        return null;
      },
      'fail': (a) =>
          throw ScriptException(a.isEmpty ? 'Script failed.' : _s(a[0])),
      'now': (a) => DateTime.now().millisecondsSinceEpoch,
      'uuid': (a) => newId(),
      'len': (a) {
        final v = a.isEmpty ? null : a[0];
        if (v is String) return v.length;
        if (v is List<Object?>) return v.length;
        if (v is Map<String, Object?>) return v.length;
        return 0;
      },
      'str': (a) => a.isEmpty ? '' : _s(a[0]),
      'num': (a) => a.isEmpty
          ? null
          : (a[0] is num ? a[0] : num.tryParse(_s(a[0]).trim())),
      'json': (a) =>
          a.isEmpty ? 'null' : jsonEncode(a[0] is HostObject ? null : a[0]),
      'parseJson': (a) {
        try {
          return jsonDecode(a.isEmpty ? '' : _s(a[0]));
        } on FormatException {
          throw const ScriptException('parseJson: invalid JSON.');
        }
      },
      'base64': (a) => base64.encode(utf8.encode(a.isEmpty ? '' : _s(a[0]))),
      'base64decode': (a) {
        try {
          return utf8.decode(base64.decode(a.isEmpty ? '' : _s(a[0])));
        } on FormatException {
          throw const ScriptException('base64decode: invalid input.');
        }
      },
      'urlencode': (a) => Uri.encodeQueryComponent(a.isEmpty ? '' : _s(a[0])),
      'sha256': (a) =>
          sha256.convert(utf8.encode(a.isEmpty ? '' : _s(a[0]))).toString(),
      'hmacSha256': (a) {
        final key = utf8.encode(a.isNotEmpty ? _s(a[0]) : '');
        final msg = utf8.encode(a.length > 1 ? _s(a[1]) : '');
        return Hmac(sha256, key).convert(msg).toString();
      },
    };
    final interp = ScriptInterpreter(
      globals: globals,
      functions: functions,
      limits: limits,
    );
    try {
      interp.run(parseScript(src));
      return (interp.steps, null);
    } on ScriptException catch (e) {
      return (interp.steps, e.toString());
    }
  }

  static bool _truthy(Object? v) =>
      !(v == null || v == false || v == 0 || v == '');
}

class _ReadOnlyRequest extends HostObject {
  _ReadOnlyRequest(this._r);
  final RequestModel _r;

  @override
  Object? getProperty(String name) {
    switch (name) {
      case 'method':
        return _r.method;
      case 'url':
        return _r.url;
      case 'body':
        return _r.body;
      case 'headers':
        return _HeadersHost(List<KeyValue>.of(_r.headers), readOnly: true);
    }
    return null;
  }

  @override
  Object? callMethod(String name, List<Object?> args) =>
      throw ScriptException('request has no method "$name".');
}
