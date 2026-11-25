import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../l10n/strings.dart';
import 'code_editor_controller.dart';
import 'editor_input_formatter.dart';
import 'find_logic.dart';
import 'highlighter.dart';
import 'json_tools.dart';
import '../../core/util/json_util.dart';
import '../widgets/pressable.dart';
import '../widgets/common.dart';

class EditorOptions {
  const EditorOptions({
    this.wordWrap = false,
    this.lineNumbers = true,
    this.tabSize = 2,
    this.autoClose = true,
    this.highlightVariables = true,
    this.reducedMotion = false,
  });

  final bool wordWrap;
  final bool lineNumbers;
  final int tabSize;
  final bool autoClose;
  final bool highlightVariables;
  final bool reducedMotion;
}

class _Layout {
  _Layout(
    this.lineTops,
    this.lineHeights,
    this.textWidth,
    this.gutterWidth,
    this.lineHeight,
  );
  final List<double> lineTops;
  final List<double> lineHeights;
  final double textWidth;
  final double gutterWidth;
  final double lineHeight;
}

TextDirection _directionOf(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

/// Reusable code editor: highlighting, line numbers, wrap toggle, auto-indent,
/// bracket matching and auto-close, find and replace (regex), go to line,
/// undo/redo, JSON format/minify and inline JSON error markers.
///
/// Not supported: code folding, virtualized rendering of very large text
/// (use LinesView for read-only large content), multi-cursor. See
/// docs/EDITOR.md.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    this.language = CodeLanguage.json,
    this.readOnly = false,
    this.options = const EditorOptions(),
    this.onWrapChanged,
    this.hintText,
    this.minHeight = 120,
    this.scrollController,
  });

  /// Optional vertical controller. Pass the page's primary controller so the
  /// editor scrolls together with the page it sits in.
  final ScrollController? scrollController;

  final CodeEditorController controller;
  final CodeLanguage language;
  final bool readOnly;
  final EditorOptions options;
  final ValueChanged<bool>? onWrapChanged;
  final String? hintText;
  final double minHeight;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final FocusNode _focus = FocusNode();
  final UndoHistoryController _undo = UndoHistoryController();
  final ScrollController _ownScroll = ScrollController();
  ScrollController get _vScroll => widget.scrollController ?? _ownScroll;
  final ScrollController _hScroll = ScrollController();
  final TextEditingController _findCtl = TextEditingController();
  final TextEditingController _replaceCtl = TextEditingController();

  bool _findOpen = false;
  bool _regex = false;
  bool _case = false;
  bool _findError = false;
  List<TextRange> _matches = const <TextRange>[];
  int _current = -1;

  JsonProblem? _problem;
  Timer? _debounce;
  String _lastText = '';
  late bool _wrap;
  _Layout? _layout;
  Object? _layoutKey;

  @override
  void initState() {
    super.initState();
    _wrap = widget.options.wordWrap;
    widget.controller.language = widget.language;
    widget.controller.highlightVariables = widget.options.highlightVariables;
    _lastText = widget.controller.text;
    widget.controller.addListener(_onController);
    _scheduleValidate();
  }

  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    widget.controller.language = widget.language;
    widget.controller.highlightVariables = widget.options.highlightVariables;
    if (old.options.wordWrap != widget.options.wordWrap) {
      _wrap = widget.options.wordWrap;
    }
    if (old.language != widget.language) _scheduleValidate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onController);
    _focus.dispose();
    _undo.dispose();
    _ownScroll.dispose();
    _hScroll.dispose();
    _findCtl.dispose();
    _replaceCtl.dispose();
    super.dispose();
  }

  void _onController() {
    final t = widget.controller.text;
    if (t == _lastText) return;
    _lastText = t;
    _scheduleValidate();
    if (_findOpen) _scheduleFind();
    if (mounted) setState(() {});
  }

  void _scheduleValidate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _validate);
  }

  void _validate() {
    if (!mounted) return;
    JsonProblem? p;
    if (widget.language == CodeLanguage.json &&
        widget.controller.text.length < 2000000) {
      p = validateJson(widget.controller.text);
    }
    widget.controller.setError(p?.offset);
    setState(() => _problem = p);
  }

  // --- find -------------------------------------------------------------

  void _scheduleFind() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _runFind(keepIndex: true);
      _validate();
    });
  }

  void _runFind({bool keepIndex = false}) {
    List<TextRange> m = const <TextRange>[];
    var err = false;
    try {
      m = findMatches(
        widget.controller.text,
        _findCtl.text,
        regex: _regex,
        caseSensitive: _case,
      );
    } on FormatException {
      err = true;
    }
    var cur = -1;
    if (m.isNotEmpty) {
      cur = keepIndex ? clampInt(_current, 0, m.length - 1) : 0;
      if (!keepIndex) {
        final caret = widget.controller.selection.isValid
            ? widget.controller.selection.baseOffset
            : 0;
        final idx = m.indexWhere((r) => r.start >= caret);
        cur = idx < 0 ? 0 : idx;
      }
    }
    widget.controller.setMatches(m, cur);
    setState(() {
      _matches = m;
      _current = cur;
      _findError = err;
    });
    if (cur >= 0 && !keepIndex) _reveal(m[cur].start);
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final i = (_current + delta) % _matches.length;
    final cur = i < 0 ? i + _matches.length : i;
    widget.controller.setMatches(_matches, cur);
    setState(() => _current = cur);
    _reveal(_matches[cur].start);
  }

  void _closeFind() {
    widget.controller.setMatches(const <TextRange>[], -1);
    setState(() {
      _findOpen = false;
      _matches = const <TextRange>[];
      _current = -1;
    });
    _focus.requestFocus();
  }

  void _openFind() {
    final sel = widget.controller.selection;
    if (sel.isValid &&
        !sel.isCollapsed &&
        !widget.controller.text.substring(sel.start, sel.end).contains('\n')) {
      _findCtl.text = widget.controller.text.substring(sel.start, sel.end);
    }
    setState(() => _findOpen = true);
    _runFind();
  }

  void _replaceCurrent() {
    if (widget.readOnly || _current < 0 || _current >= _matches.length) return;
    final c = widget.controller;
    final next = replaceOne(
      c.text,
      _matches[_current],
      _findCtl.text,
      _replaceCtl.text,
      regex: _regex,
      caseSensitive: _case,
    );
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: _matches[_current].start),
    );
    _runFind(keepIndex: true);
  }

  void _replaceAll() {
    if (widget.readOnly || _findCtl.text.isEmpty) return;
    final c = widget.controller;
    try {
      final next = replaceAllMatches(
        c.text,
        _findCtl.text,
        _replaceCtl.text,
        regex: _regex,
        caseSensitive: _case,
      );
      c.value = TextEditingValue(
        text: next,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _runFind();
    } on FormatException {
      setState(() => _findError = true);
    }
  }

  // --- navigation -------------------------------------------------------

  void _reveal(int offset) {
    final layout = _layout;
    if (layout == null || !_vScroll.hasClients) return;
    final text = widget.controller.text;
    var line = 0;
    final end = math.min(offset, text.length);
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    if (line >= layout.lineTops.length) return;
    final y = layout.lineTops[line] + 8;
    final pos = _vScroll.position;
    final target = clampDouble(
      y - pos.viewportDimension * 0.3,
      0.0,
      pos.maxScrollExtent,
    );
    if (widget.options.reducedMotion) {
      _vScroll.jumpTo(target);
    } else {
      unawaited(
        _vScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _goToLine() async {
    final total = '\n'.allMatches(widget.controller.text).length + 1;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => WithTextController(
        builder: (ctx, ctl) => AlertDialog(
          title: Text(ctx.t('editor.goToLine')),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(hintText: '1 - $total'),
            onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text)),
              child: Text(ctx.t('common.ok')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final target = clampInt(result, 1, total);
    final text = widget.controller.text;
    var offset = 0;
    var line = 1;
    while (line < target) {
      final nl = text.indexOf('\n', offset);
      if (nl < 0) break;
      offset = nl + 1;
      line++;
    }
    widget.controller.selection = TextSelection.collapsed(offset: offset);
    _focus.requestFocus();
    _reveal(offset);
  }

  void _format() {
    final out = formatJson(
      widget.controller.text,
      indent: widget.options.tabSize,
    );
    if (out == null) {
      unawaited(showToast(context, context.t('editor.formatFailed')));
      return;
    }
    widget.controller.value = TextEditingValue(
      text: out,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _minify() {
    final out = minifyJson(widget.controller.text);
    if (out == null) {
      unawaited(showToast(context, context.t('editor.formatFailed')));
      return;
    }
    widget.controller.value = TextEditingValue(
      text: out,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _indent({required bool outdent}) {
    final c = widget.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    final pad = ' ' * widget.options.tabSize;
    if (!outdent && sel.isCollapsed) {
      c.value = c.value
          .replaced(sel, pad)
          .copyWith(
            selection: TextSelection.collapsed(offset: sel.start + pad.length),
          );
      return;
    }
    final text = c.text;
    final start = text.lastIndexOf('\n', math.max(0, sel.start - 1)) + 1;
    final end = sel.end;
    final block = text.substring(start, end);
    final lines = block.split('\n');
    final mapped = lines.map((l) {
      if (!outdent) return '$pad$l';
      var k = 0;
      while (k < widget.options.tabSize && k < l.length && l[k] == ' ') {
        k++;
      }
      return l.substring(k);
    }).toList();
    final next = text.replaceRange(start, end, mapped.join('\n'));
    final delta = mapped.join('\n').length - block.length;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: math.max(0, sel.start + (outdent ? 0 : pad.length)),
        extentOffset: sel.end + delta,
      ),
    );
  }

  // --- layout -----------------------------------------------------------

  _Layout _computeLayout(
    double maxWidth,
    TextStyle style,
    StrutStyle strut,
    TextDirection dir,
  ) {
    final text = widget.controller.text;
    final showNumbers = widget.options.lineNumbers;
    final key = Object.hash(
      text.length,
      text.hashCode,
      _wrap,
      maxWidth.round(),
      style.fontSize,
      showNumbers,
    );
    if (_layout != null && _layoutKey == key) return _layout!;

    final probe = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
      strutStyle: strut,
    )..layout();
    final lineH = probe.height;
    final charW = probe.width;
    probe.dispose();

    final lines = text.split('\n');
    final digits = math.max(2, '${lines.length}'.length);
    final gutter = showNumbers && lines.length <= 5000
        ? digits * charW + 18
        : 0.0;
    final avail = math.max(60.0, maxWidth - gutter);

    var longest = 0;
    for (final l in lines) {
      if (l.length > longest) longest = l.length;
    }
    final textWidth = _wrap
        ? avail
        : math.max(avail, math.min(longest * charW + 32, 200000.0));

    final heights = List<double>.filled(lines.length, lineH);
    if (_wrap && lines.length <= 3000) {
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.length * charW + 16 <= avail) continue;
        final p = TextPainter(
          text: TextSpan(text: l, style: style),
          textDirection: dir,
          strutStyle: strut,
        )..layout(maxWidth: math.max(20.0, avail - 16));
        heights[i] = math.max(lineH, p.height);
        p.dispose();
      }
    }
    final tops = List<double>.filled(lines.length, 0);
    var y = 0.0;
    for (var i = 0; i < lines.length; i++) {
      tops[i] = y;
      y += heights[i];
    }
    _layout = _Layout(tops, heights, textWidth, gutter, lineH);
    _layoutKey = key;
    return _layout!;
  }

  // --- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.codeStyle;
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final text = widget.controller.text;
    final dir = widget.language == CodeLanguage.json
        ? TextDirection.ltr
        : _directionOf(text);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openFind,
      const SingleActivator(LogicalKeyboardKey.keyG, control: true): _goToLine,
      if (_findOpen)
        const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
      if (!widget.readOnly)
        const SingleActivator(LogicalKeyboardKey.tab): () =>
            _indent(outdent: false),
      if (!widget.readOnly)
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            _indent(outdent: true),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Container(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            _buildToolbar(context),
            if (_findOpen) _buildFindBar(context),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  final layout = _computeLayout(
                    cons.maxWidth,
                    style,
                    strut,
                    dir,
                  );
                  return _buildBody(ctx, cons, layout, style, strut, dir);
                },
              ),
            ),
            if (_problem != null) _buildProblem(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    BoxConstraints cons,
    _Layout layout,
    TextStyle style,
    StrutStyle strut,
    TextDirection dir,
  ) {
    final c = context.colors;
    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      undoController: _undo,
      readOnly: widget.readOnly,
      maxLines: null,
      style: style,
      strutStyle: strut,
      textDirection: dir,
      cursorColor: c.accent,
      keyboardType: TextInputType.multiline,
      enableSuggestions: false,
      autocorrect: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      scrollPhysics: const NeverScrollableScrollPhysics(),
      inputFormatters: <TextInputFormatter>[
        EditorInputFormatter(
          language: widget.language,
          tabSize: widget.options.tabSize,
          autoClose: widget.options.autoClose,
        ),
      ],
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: widget.hintText,
        hintStyle: style.copyWith(color: c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );

    final errorLine = _problem == null ? -1 : _problem!.line - 1;
    final gutter = layout.gutterWidth > 0
        ? Container(
            width: layout.gutterWidth,
            padding: const EdgeInsets.only(top: 8, right: 6, left: 6),
            color: c.surfaceBase,
            child: Column(
              children: <Widget>[
                for (var i = 0; i < layout.lineHeights.length; i++)
                  SizedBox(
                    height: layout.lineHeights[i],
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Text(
                        '${i + 1}',
                        textDirection: TextDirection.ltr,
                        style: style.copyWith(
                          color: i == errorLine ? c.danger : c.textSecondary,
                          fontWeight: i == errorLine ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final area = _wrap
        ? SizedBox(width: layout.textWidth, child: field)
        : Directionality(
            // Horizontal scrolling starts at the left edge even in RTL, so
            // the first characters of every line stay in view.
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: Directionality(
                textDirection: dir,
                child: SizedBox(width: layout.textWidth, child: field),
              ),
            ),
          );

    return Scrollbar(
      // A shared page controller may have several positions while tabs
      // change, so the scrollbar then follows its child instead.
      controller: widget.scrollController == null ? _ownScroll : null,
      child: SingleChildScrollView(
        controller: _vScroll,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focus.requestFocus(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: cons.maxHeight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: TextDirection.ltr,
              children: <Widget>[
                gutter,
                Expanded(child: area),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tool(
    IconData icon,
    String tip,
    VoidCallback? onTap, {
    bool active = false,
  }) {
    final c = context.colors;
    return IconButton(
      icon: Icon(
        icon,
        size: 18,
        color: onTap == null ? c.border : (active ? c.accent : c.textSecondary),
      ),
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final c = context.colors;
    final ro = widget.readOnly;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            if (!ro)
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: _undo,
                builder: (ctx, v, _) => Row(
                  children: <Widget>[
                    _tool(
                      Icons.undo,
                      ctx.t('editor.undo'),
                      v.canUndo ? _undo.undo : null,
                    ),
                    _tool(
                      Icons.redo,
                      ctx.t('editor.redo'),
                      v.canRedo ? _undo.redo : null,
                    ),
                  ],
                ),
              ),
            _tool(
              Icons.search,
              context.t('editor.find'),
              _findOpen ? _closeFind : _openFind,
              active: _findOpen,
            ),
            _tool(
              Icons.format_list_numbered,
              context.t('editor.goToLine'),
              _goToLine,
            ),
            if (widget.language == CodeLanguage.json && !ro) ...<Widget>[
              _tool(
                Icons.format_align_left,
                context.t('editor.format'),
                _format,
              ),
              _tool(Icons.compress, context.t('editor.minify'), _minify),
            ],
            _tool(Icons.wrap_text, context.t('editor.wrap'), () {
              setState(() => _wrap = !_wrap);
              widget.onWrapChanged?.call(_wrap);
            }, active: _wrap),
            _tool(Icons.copy, context.t('editor.copy'), () async {
              await Clipboard.setData(
                ClipboardData(text: widget.controller.text),
              );
              if (context.mounted) {
                await showToast(context, context.t('common.copied'));
              }
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFindBar(BuildContext context) {
    final c = context.colors;
    String count() {
      if (_findError) return context.t('editor.badRegex');
      if (_findCtl.text.isEmpty) return '';
      if (_matches.isEmpty) return context.t('editor.noMatches');
      return '${_current + 1}/${_matches.length}';
    }

    Widget toggle(String label, String tip, bool on, VoidCallback f) => Tooltip(
      message: tip,
      child: Pressable(
        borderRadius: BorderRadius.circular(4),
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: on ? c.accent.withAlpha(40) : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: on ? c.accent : c.border),
          ),
          child: Text(
            label,
            style: context.mono.copyWith(
              fontSize: 12,
              color: on ? c.accent : c.textSecondary,
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.surfaceBase,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _findCtl,
                    autofocus: true,
                    style: context.mono,
                    decoration: InputDecoration(
                      hintText: context.t('editor.find'),
                      errorText: null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      enabledBorder: _findError
                          ? OutlineInputBorder(
                              borderSide: BorderSide(color: c.danger),
                            )
                          : null,
                    ),
                    onChanged: (_) => _runFind(),
                    onSubmitted: (_) => _step(1),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              toggle('.*', context.t('editor.regex'), _regex, () {
                setState(() => _regex = !_regex);
                _runFind();
              }),
              const SizedBox(width: 4),
              toggle('Aa', context.t('editor.matchCase'), _case, () {
                setState(() => _case = !_case);
                _runFind();
              }),
              const SizedBox(width: 6),
              Text(count(), style: context.secondary),
              _tool(
                Icons.keyboard_arrow_up,
                context.t('editor.prev'),
                () => _step(-1),
              ),
              _tool(
                Icons.keyboard_arrow_down,
                context.t('editor.next'),
                () => _step(1),
              ),
              _tool(Icons.close, context.t('common.close'), _closeFind),
            ],
          ),
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _replaceCtl,
                        style: context.mono,
                        decoration: InputDecoration(
                          hintText: context.t('editor.replaceWith'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _replaceCurrent,
                    child: Text(context.t('editor.replace')),
                  ),
                  TextButton(
                    onPressed: _replaceAll,
                    child: Text(context.t('editor.replaceAll')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProblem(BuildContext context) {
    final c = context.colors;
    final p = _problem!;
    return Pressable(
      onTap: () {
        widget.controller.selection = TextSelection.collapsed(offset: p.offset);
        _focus.requestFocus();
        _reveal(p.offset);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.surfaceBase,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 16, color: c.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.t('editor.jsonError', <String>[
                  '${p.line}',
                  '${p.column}',
                  p.message,
                ]),
                style: context.secondary.copyWith(color: c.danger),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
