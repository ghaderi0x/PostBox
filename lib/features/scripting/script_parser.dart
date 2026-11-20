/// Parser for PostBox Script, the small sandboxed language used by pre-request
/// and post-response scripts. See docs/SCRIPTING.md.
///
/// It looks like a tiny subset of JavaScript: `let`, assignments, `if`/`else`,
/// `for x in list`, function and method calls, literals, and the usual
/// operators. There is no way to loop forever, read files, open sockets or
/// reach the app's secrets: scripts only see what the host objects expose.
library;

class ScriptException implements Exception {
  const ScriptException(this.message, [this.line]);
  final String message;
  final int? line;

  @override
  String toString() => line == null ? message : 'Line $line: $message';
}

enum TokenType { number, string, ident, op, eof }

class Token {
  const Token(this.type, this.text, this.line, [this.number]);
  final TokenType type;
  final String text;
  final int line;
  final num? number;

  bool isOp(String s) => type == TokenType.op && text == s;
  bool isKeyword(String s) => type == TokenType.ident && text == s;
}

const Set<String> _keywords = <String>{
  'let',
  'if',
  'else',
  'for',
  'in',
  'true',
  'false',
  'null',
};

List<Token> tokenize(String src) {
  final out = <Token>[];
  var i = 0;
  var line = 1;
  bool isDigit(int c) => c >= 48 && c <= 57;
  bool isIdStart(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36;
  while (i < src.length) {
    final c = src.codeUnitAt(i);
    if (c == 10) {
      line++;
      i++;
    } else if (c == 32 || c == 9 || c == 13) {
      i++;
    } else if (c == 47 && i + 1 < src.length && src.codeUnitAt(i + 1) == 47) {
      while (i < src.length && src.codeUnitAt(i) != 10) {
        i++;
      }
    } else if (isDigit(c)) {
      final start = i;
      while (i < src.length &&
          (isDigit(src.codeUnitAt(i)) || src.codeUnitAt(i) == 46)) {
        i++;
      }
      final text = src.substring(start, i);
      final n = num.tryParse(text);
      if (n == null) throw ScriptException('Bad number "$text"', line);
      out.add(Token(TokenType.number, text, line, n));
    } else if (isIdStart(c)) {
      final start = i;
      while (i < src.length &&
          (isIdStart(src.codeUnitAt(i)) || isDigit(src.codeUnitAt(i)))) {
        i++;
      }
      out.add(Token(TokenType.ident, src.substring(start, i), line));
    } else if (c == 34 || c == 39) {
      final quote = c;
      final buf = StringBuffer();
      i++;
      var closed = false;
      while (i < src.length) {
        final d = src.codeUnitAt(i);
        if (d == quote) {
          closed = true;
          i++;
          break;
        }
        if (d == 10) break;
        if (d == 92 && i + 1 < src.length) {
          final e = src[i + 1];
          switch (e) {
            case 'n':
              buf.write('\n');
            case 't':
              buf.write('\t');
            case 'r':
              buf.write('\r');
            default:
              buf.write(e);
          }
          i += 2;
        } else {
          buf.writeCharCode(d);
          i++;
        }
      }
      if (!closed) throw ScriptException('Unterminated string', line);
      out.add(Token(TokenType.string, buf.toString(), line));
    } else {
      const two = <String>['==', '!=', '<=', '>=', '&&', '||', '??'];
      final pair = i + 1 < src.length ? src.substring(i, i + 2) : '';
      if (two.contains(pair)) {
        out.add(Token(TokenType.op, pair, line));
        i += 2;
      } else if ('+-*/%<>=!(){}[],.:;'.contains(src[i])) {
        out.add(Token(TokenType.op, src[i], line));
        i++;
      } else {
        throw ScriptException('Unexpected character "${src[i]}"', line);
      }
    }
  }
  out.add(Token(TokenType.eof, '', line));
  return out;
}

// ---- AST ----------------------------------------------------------------

sealed class Expr {
  const Expr(this.line);
  final int line;
}

class Lit extends Expr {
  const Lit(this.value, super.line);
  final Object? value;
}

class Ident extends Expr {
  const Ident(this.name, super.line);
  final String name;
}

class ListLit extends Expr {
  const ListLit(this.items, super.line);
  final List<Expr> items;
}

class MapLit extends Expr {
  const MapLit(this.entries, super.line);
  final List<(String, Expr)> entries;
}

class Unary extends Expr {
  const Unary(this.op, this.operand, super.line);
  final String op;
  final Expr operand;
}

class Binary extends Expr {
  const Binary(this.op, this.left, this.right, super.line);
  final String op;
  final Expr left;
  final Expr right;
}

class Member extends Expr {
  const Member(this.target, this.name, super.line);
  final Expr target;
  final String name;
}

class Index extends Expr {
  const Index(this.target, this.index, super.line);
  final Expr target;
  final Expr index;
}

class Call extends Expr {
  const Call(this.callee, this.args, super.line);
  final Expr callee;
  final List<Expr> args;
}

sealed class Stmt {
  const Stmt(this.line);
  final int line;
}

class LetStmt extends Stmt {
  const LetStmt(this.name, this.value, super.line);
  final String name;
  final Expr value;
}

class AssignStmt extends Stmt {
  const AssignStmt(this.target, this.value, super.line);
  final Expr target;
  final Expr value;
}

class ExprStmt extends Stmt {
  const ExprStmt(this.expr, super.line);
  final Expr expr;
}

class IfStmt extends Stmt {
  const IfStmt(this.cond, this.thenBody, this.elseBody, super.line);
  final Expr cond;
  final List<Stmt> thenBody;
  final List<Stmt>? elseBody;
}

class ForStmt extends Stmt {
  const ForStmt(this.name, this.iterable, this.body, super.line);
  final String name;
  final Expr iterable;
  final List<Stmt> body;
}

// ---- Parser ---------------------------------------------------------------

/// Hard limits so a pasted script cannot exhaust memory while parsing.
const int kMaxScriptChars = 100000;
const int kMaxNesting = 40;

List<Stmt> parseScript(String src) {
  if (src.length > kMaxScriptChars) {
    throw const ScriptException('Script is too long.');
  }
  return _Parser(tokenize(src)).program();
}

class _Parser {
  _Parser(this._t);

  final List<Token> _t;
  var _p = 0;
  var _depth = 0;

  Token get _cur => _t[_p];
  Token _next() => _t[_p++];

  bool _matchOp(String s) {
    if (_cur.isOp(s)) {
      _p++;
      return true;
    }
    return false;
  }

  void _expectOp(String s) {
    if (!_matchOp(s)) {
      throw ScriptException(
        'Expected "$s" but found "${_cur.text}"',
        _cur.line,
      );
    }
  }

  String _expectIdent() {
    final t = _next();
    if (t.type != TokenType.ident || _keywords.contains(t.text)) {
      throw ScriptException('Expected a name but found "${t.text}"', t.line);
    }
    return t.text;
  }

  List<Stmt> program() {
    final out = <Stmt>[];
    while (_cur.type != TokenType.eof) {
      out.add(_stmt());
    }
    return out;
  }

  List<Stmt> _block() {
    _expectOp('{');
    if (++_depth > kMaxNesting) {
      throw ScriptException('Blocks are nested too deeply.', _cur.line);
    }
    final out = <Stmt>[];
    while (!_cur.isOp('}')) {
      if (_cur.type == TokenType.eof) {
        throw ScriptException('Missing "}"', _cur.line);
      }
      out.add(_stmt());
    }
    _expectOp('}');
    _depth--;
    return out;
  }

  Stmt _stmt() {
    final line = _cur.line;
    if (_cur.isKeyword('let')) {
      _p++;
      final name = _expectIdent();
      _expectOp('=');
      final v = _expr();
      _matchOp(';');
      return LetStmt(name, v, line);
    }
    if (_cur.isKeyword('if')) return _ifStmt();
    if (_cur.isKeyword('for')) {
      _p++;
      final name = _expectIdent();
      if (!_cur.isKeyword('in')) {
        throw ScriptException('Expected "in"', _cur.line);
      }
      _p++;
      final it = _expr();
      return ForStmt(name, it, _block(), line);
    }
    final e = _expr();
    if (_matchOp('=')) {
      if (e is! Ident && e is! Member && e is! Index) {
        throw ScriptException('Cannot assign to this expression', line);
      }
      final v = _expr();
      _matchOp(';');
      return AssignStmt(e, v, line);
    }
    _matchOp(';');
    return ExprStmt(e, line);
  }

  Stmt _ifStmt() {
    final line = _cur.line;
    _p++; // if
    _expectOp('(');
    final cond = _expr();
    _expectOp(')');
    final thenBody = _block();
    List<Stmt>? elseBody;
    if (_cur.isKeyword('else')) {
      _p++;
      elseBody = _cur.isKeyword('if') ? <Stmt>[_ifStmt()] : _block();
    }
    return IfStmt(cond, thenBody, elseBody, line);
  }

  Expr _expr() {
    if (++_depth > kMaxNesting * 4) {
      throw ScriptException('Expression is nested too deeply.', _cur.line);
    }
    final e = _coalesce();
    _depth--;
    return e;
  }

  Expr _coalesce() {
    var l = _or();
    while (_cur.isOp('??')) {
      final line = _next().line;
      l = Binary('??', l, _or(), line);
    }
    return l;
  }

  Expr _or() {
    var l = _and();
    while (_cur.isOp('||')) {
      final line = _next().line;
      l = Binary('||', l, _and(), line);
    }
    return l;
  }

  Expr _and() {
    var l = _equality();
    while (_cur.isOp('&&')) {
      final line = _next().line;
      l = Binary('&&', l, _equality(), line);
    }
    return l;
  }

  Expr _equality() {
    var l = _comparison();
    while (_cur.isOp('==') || _cur.isOp('!=')) {
      final t = _next();
      l = Binary(t.text, l, _comparison(), t.line);
    }
    return l;
  }

  Expr _comparison() {
    var l = _additive();
    while (_cur.isOp('<') ||
        _cur.isOp('<=') ||
        _cur.isOp('>') ||
        _cur.isOp('>=')) {
      final t = _next();
      l = Binary(t.text, l, _additive(), t.line);
    }
    return l;
  }

  Expr _additive() {
    var l = _multiplicative();
    while (_cur.isOp('+') || _cur.isOp('-')) {
      final t = _next();
      l = Binary(t.text, l, _multiplicative(), t.line);
    }
    return l;
  }

  Expr _multiplicative() {
    var l = _unary();
    while (_cur.isOp('*') || _cur.isOp('/') || _cur.isOp('%')) {
      final t = _next();
      l = Binary(t.text, l, _unary(), t.line);
    }
    return l;
  }

  Expr _unary() {
    if (_cur.isOp('!') || _cur.isOp('-')) {
      final t = _next();
      return Unary(t.text, _unary(), t.line);
    }
    return _postfix();
  }

  Expr _postfix() {
    var e = _primary();
    while (true) {
      if (_cur.isOp('.')) {
        final line = _next().line;
        final name = _next();
        if (name.type != TokenType.ident) {
          throw ScriptException('Expected a property name after "."', line);
        }
        e = Member(e, name.text, line);
      } else if (_cur.isOp('[')) {
        final line = _next().line;
        final idx = _expr();
        _expectOp(']');
        e = Index(e, idx, line);
      } else if (_cur.isOp('(')) {
        final line = _next().line;
        final args = <Expr>[];
        if (!_cur.isOp(')')) {
          do {
            args.add(_expr());
          } while (_matchOp(','));
        }
        _expectOp(')');
        e = Call(e, args, line);
      } else {
        return e;
      }
    }
  }

  Expr _primary() {
    final t = _next();
    switch (t.type) {
      case TokenType.number:
        return Lit(t.number, t.line);
      case TokenType.string:
        return Lit(t.text, t.line);
      case TokenType.ident:
        switch (t.text) {
          case 'true':
            return Lit(true, t.line);
          case 'false':
            return Lit(false, t.line);
          case 'null':
            return Lit(null, t.line);
        }
        if (_keywords.contains(t.text)) {
          throw ScriptException('Unexpected "${t.text}"', t.line);
        }
        return Ident(t.text, t.line);
      case TokenType.op:
        if (t.text == '(') {
          final e = _expr();
          _expectOp(')');
          return e;
        }
        if (t.text == '[') {
          final items = <Expr>[];
          if (!_cur.isOp(']')) {
            do {
              if (_cur.isOp(']')) break;
              items.add(_expr());
            } while (_matchOp(','));
          }
          _expectOp(']');
          return ListLit(items, t.line);
        }
        if (t.text == '{') {
          final entries = <(String, Expr)>[];
          if (!_cur.isOp('}')) {
            do {
              if (_cur.isOp('}')) break;
              final k = _next();
              if (k.type != TokenType.string && k.type != TokenType.ident) {
                throw ScriptException('Expected a key', k.line);
              }
              _expectOp(':');
              entries.add((k.text, _expr()));
            } while (_matchOp(','));
          }
          _expectOp('}');
          return MapLit(entries, t.line);
        }
        throw ScriptException('Unexpected "${t.text}"', t.line);
      case TokenType.eof:
        throw ScriptException('Unexpected end of script', t.line);
    }
  }
}
