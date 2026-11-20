import 'dart:convert';

import 'script_parser.dart';

/// Something the host (PostBox) exposes to scripts, such as `vars`,
/// `request` or `response`. Scripts can only touch what these methods allow.
abstract class HostObject {
  Object? getProperty(String name);

  void setProperty(String name, Object? value) {
    throw ScriptException('"$name" is read-only.');
  }

  Object? callMethod(String name, List<Object?> args);
}

typedef ScriptFunction = Object? Function(List<Object?> args);

/// Resource limits for one script run.
class ScriptLimits {
  const ScriptLimits({
    this.maxSteps = 50000,
    this.maxDuration = const Duration(seconds: 2),
    this.maxStringLength = 1000000,
    this.maxListLength = 10000,
  });

  final int maxSteps;
  final Duration maxDuration;
  final int maxStringLength;
  final int maxListLength;
}

/// Tree-walking interpreter with hard resource limits. Not re-entrant.
class ScriptInterpreter {
  ScriptInterpreter({
    required Map<String, Object?> globals,
    required Map<String, ScriptFunction> functions,
    this.limits = const ScriptLimits(),
  }) : _functions = functions,
       _scopes = <Map<String, Object?>>[Map<String, Object?>.of(globals)];

  final ScriptLimits limits;
  final Map<String, ScriptFunction> _functions;
  final List<Map<String, Object?>> _scopes;
  final Stopwatch _clock = Stopwatch();
  int _steps = 0;

  int get steps => _steps;

  void run(List<Stmt> program) {
    _clock.start();
    try {
      _execBlock(program, newScope: false);
    } finally {
      _clock.stop();
    }
  }

  void _tick(int line) {
    if (++_steps > limits.maxSteps) {
      throw ScriptException(
        'Script used too many steps (limit ${limits.maxSteps}).',
        line,
      );
    }
    if ((_steps & 255) == 0 && _clock.elapsed > limits.maxDuration) {
      throw ScriptException(
        'Script ran longer than ${limits.maxDuration.inSeconds}s.',
        line,
      );
    }
  }

  void _execBlock(List<Stmt> body, {bool newScope = true}) {
    if (newScope) _scopes.add(<String, Object?>{});
    try {
      for (final s in body) {
        _exec(s);
      }
    } finally {
      if (newScope) _scopes.removeLast();
    }
  }

  void _exec(Stmt s) {
    _tick(s.line);
    switch (s) {
      case LetStmt():
        _scopes.last[s.name] = _eval(s.value);
      case AssignStmt():
        _assign(s.target, _eval(s.value));
      case ExprStmt():
        _eval(s.expr);
      case IfStmt():
        if (_truthy(_eval(s.cond))) {
          _execBlock(s.thenBody);
        } else if (s.elseBody != null) {
          _execBlock(s.elseBody!);
        }
      case ForStmt():
        final it = _eval(s.iterable);
        final Iterable<Object?> items;
        if (it is List<Object?>) {
          items = List<Object?>.of(it);
        } else if (it is Map<String, Object?>) {
          items = List<Object?>.of(it.keys);
        } else {
          throw ScriptException(
            'Can only loop over a list or an object.',
            s.line,
          );
        }
        for (final item in items) {
          _tick(s.line);
          _scopes.add(<String, Object?>{s.name: item});
          try {
            for (final b in s.body) {
              _exec(b);
            }
          } finally {
            _scopes.removeLast();
          }
        }
    }
  }

  Map<String, Object?>? _scopeOf(String name) {
    for (var i = _scopes.length - 1; i >= 0; i--) {
      if (_scopes[i].containsKey(name)) return _scopes[i];
    }
    return null;
  }

  void _assign(Expr target, Object? value) {
    switch (target) {
      case Ident():
        final scope = _scopeOf(target.name);
        if (scope == null) {
          throw ScriptException(
            '"${target.name}" is not defined. Use let first.',
            target.line,
          );
        }
        scope[target.name] = value;
      case Member():
        final obj = _eval(target.target);
        if (obj is HostObject) {
          obj.setProperty(target.name, value);
        } else if (obj is Map<String, Object?>) {
          obj[target.name] = value;
        } else {
          throw ScriptException(
            'Cannot set "${target.name}" here.',
            target.line,
          );
        }
      case Index():
        final obj = _eval(target.target);
        final idx = _eval(target.index);
        if (obj is HostObject) {
          obj.setProperty(_str(idx), value);
        } else if (obj is Map<String, Object?>) {
          obj[_str(idx)] = value;
        } else if (obj is List<Object?> && idx is num) {
          final i = idx.toInt();
          if (i < 0 || i >= obj.length) {
            throw ScriptException('Index $i is out of range.', target.line);
          }
          obj[i] = value;
        } else {
          throw ScriptException('Cannot assign by index here.', target.line);
        }
      default:
        throw ScriptException('Cannot assign to this expression.', target.line);
    }
  }

  static bool _truthy(Object? v) =>
      !(v == null || v == false || v == 0 || v == '');

  static String _str(Object? v) {
    if (v == null) return 'null';
    if (v is String) return v;
    if (v is num) {
      return v is double && v == v.truncateToDouble() && v.abs() < 1e15
          ? v.toInt().toString()
          : v.toString();
    }
    if (v is bool) return v.toString();
    if (v is HostObject) return '[object]';
    try {
      return jsonEncode(v);
    } on Object {
      return v.toString();
    }
  }

  static bool _equals(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is List<Object?> && b is List<Object?>) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map<String, Object?> && b is Map<String, Object?>) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_equals(a[k], b[k])) return false;
      }
      return true;
    }
    return a == b;
  }

  Object? _eval(Expr e) {
    _tick(e.line);
    switch (e) {
      case Lit():
        return e.value;
      case Ident():
        final scope = _scopeOf(e.name);
        if (scope == null) {
          throw ScriptException('"${e.name}" is not defined.', e.line);
        }
        return scope[e.name];
      case ListLit():
        if (e.items.length > limits.maxListLength) {
          throw ScriptException('List is too long.', e.line);
        }
        return <Object?>[for (final i in e.items) _eval(i)];
      case MapLit():
        return <String, Object?>{for (final (k, v) in e.entries) k: _eval(v)};
      case Unary():
        final v = _eval(e.operand);
        if (e.op == '!') return !_truthy(v);
        if (v is! num) throw ScriptException('"-" needs a number.', e.line);
        return -v;
      case Binary():
        return _binary(e);
      case Member():
        return _member(_eval(e.target), e.name, e.line);
      case Index():
        return _index(_eval(e.target), _eval(e.index), e.line);
      case Call():
        return _call(e);
    }
  }

  Object? _binary(Binary e) {
    // Short-circuit operators evaluate the right side only when needed.
    if (e.op == '&&') {
      final l = _eval(e.left);
      return _truthy(l) ? _eval(e.right) : l;
    }
    if (e.op == '||') {
      final l = _eval(e.left);
      return _truthy(l) ? l : _eval(e.right);
    }
    if (e.op == '??') {
      final l = _eval(e.left);
      return l ?? _eval(e.right);
    }
    final l = _eval(e.left);
    final r = _eval(e.right);
    switch (e.op) {
      case '==':
        return _equals(l, r);
      case '!=':
        return !_equals(l, r);
      case '+':
        if (l is num && r is num) return l + r;
        if (l is String || r is String) {
          final s = _str(l) + _str(r);
          if (s.length > limits.maxStringLength) {
            throw ScriptException('String is too long.', e.line);
          }
          return s;
        }
        if (l is List<Object?> && r is List<Object?>) {
          if (l.length + r.length > limits.maxListLength) {
            throw ScriptException('List is too long.', e.line);
          }
          return <Object?>[...l, ...r];
        }
        throw ScriptException('"+" needs numbers, strings or lists.', e.line);
      case '-':
      case '*':
      case '/':
      case '%':
        if (l is! num || r is! num) {
          throw ScriptException('"${e.op}" needs numbers.', e.line);
        }
        switch (e.op) {
          case '-':
            return l - r;
          case '*':
            return l * r;
          case '/':
            if (r == 0) throw ScriptException('Division by zero.', e.line);
            final q = l / r;
            return q == q.truncateToDouble() ? q.toInt() : q;
          default:
            if (r == 0) throw ScriptException('Division by zero.', e.line);
            return l % r;
        }
      case '<':
      case '<=':
      case '>':
      case '>=':
        final int c;
        if (l is num && r is num) {
          c = l.compareTo(r);
        } else if (l is String && r is String) {
          c = l.compareTo(r);
        } else {
          throw ScriptException(
            '"${e.op}" compares two numbers or two strings.',
            e.line,
          );
        }
        return switch (e.op) {
          '<' => c < 0,
          '<=' => c <= 0,
          '>' => c > 0,
          _ => c >= 0,
        };
    }
    throw ScriptException('Unknown operator "${e.op}".', e.line);
  }

  Object? _member(Object? target, String name, int line) {
    if (target is HostObject) return target.getProperty(name);
    if (target is Map<String, Object?>) return target[name];
    if (target is List<Object?> && name == 'length') return target.length;
    if (target is String && name == 'length') return target.length;
    if (target == null) {
      throw ScriptException('Cannot read "$name" of null.', line);
    }
    throw ScriptException('Unknown property "$name".', line);
  }

  Object? _index(Object? target, Object? idx, int line) {
    if (target is List<Object?> && idx is num) {
      final i = idx.toInt();
      return i >= 0 && i < target.length ? target[i] : null;
    }
    if (target is Map<String, Object?>) return target[_str(idx)];
    if (target is String && idx is num) {
      final i = idx.toInt();
      return i >= 0 && i < target.length ? target[i] : null;
    }
    if (target is HostObject) return target.getProperty(_str(idx));
    throw ScriptException('Cannot index this value.', line);
  }

  Object? _call(Call e) {
    final args = <Object?>[for (final a in e.args) _eval(a)];
    final callee = e.callee;
    if (callee is Ident) {
      final f = _functions[callee.name];
      if (f == null) {
        throw ScriptException('Unknown function "${callee.name}".', e.line);
      }
      return f(args);
    }
    if (callee is Member) {
      final target = _eval(callee.target);
      if (target is HostObject) return target.callMethod(callee.name, args);
      return _builtinMethod(target, callee.name, args, e.line);
    }
    throw ScriptException('This expression cannot be called.', e.line);
  }

  Object? _builtinMethod(Object? t, String name, List<Object?> a, int line) {
    String arg(int i) => i < a.length ? _str(a[i]) : '';
    if (t is String) {
      switch (name) {
        case 'contains':
          return t.contains(arg(0));
        case 'startsWith':
          return t.startsWith(arg(0));
        case 'endsWith':
          return t.endsWith(arg(0));
        case 'toUpperCase':
          return t.toUpperCase();
        case 'toLowerCase':
          return t.toLowerCase();
        case 'trim':
          return t.trim();
        case 'split':
          return <Object?>[...t.split(arg(0))];
        case 'replace':
          return t.replaceAll(arg(0), arg(1));
        case 'substring':
          final from = a.isNotEmpty && a[0] is num ? (a[0] as num).toInt() : 0;
          final to = a.length > 1 && a[1] is num
              ? (a[1] as num).toInt()
              : t.length;
          return t.substring(from.clamp(0, t.length), to.clamp(0, t.length));
      }
    } else if (t is List<Object?>) {
      switch (name) {
        case 'contains':
          return t.any((x) => _equals(x, a.isEmpty ? null : a[0]));
        case 'join':
          return t.map(_str).join(a.isEmpty ? ',' : arg(0));
        case 'push':
          if (t.length >= limits.maxListLength) {
            throw ScriptException('List is too long.', line);
          }
          t.add(a.isEmpty ? null : a[0]);
          return t.length;
      }
    } else if (t is Map<String, Object?>) {
      switch (name) {
        case 'has':
          return t.containsKey(arg(0));
        case 'keys':
          return <Object?>[...t.keys];
      }
    }
    throw ScriptException('Unknown method "$name".', line);
  }

  /// Display form used by `log()` and error messages.
  static String display(Object? v) => _str(v);
}
