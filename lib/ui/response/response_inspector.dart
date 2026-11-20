import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/file_service.dart';
import '../../core/util/format.dart';
import '../../core/util/redact.dart';
import '../../features/http/application/request_executor.dart';
import '../../features/http/domain/http_engine.dart';
import '../../features/testing/domain/line_diff.dart';
import '../../features/requests/domain/request_models.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../editor/code_editor_controller.dart';
import '../editor/highlighter.dart';
import '../editor/json_tools.dart';
import '../editor/lines_view.dart';
import '../editor/settings_code_editor.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';
import 'html_browser_view.dart';
import 'json_tree.dart';
import 'stream_view.dart';
import 'timeline_view.dart';

enum _Kind { json, xml, html, text, image, media, binary }

_Kind _classify(HttpResult r) {
  final ct = (r.contentType ?? '').toLowerCase();
  if (ct.startsWith('image/') && !ct.contains('svg')) return _Kind.image;
  if (ct.startsWith('audio/') || ct.startsWith('video/')) return _Kind.media;
  if (ct.contains('json')) return _Kind.json;
  if (ct.contains('html')) return _Kind.html;
  if (ct.contains('xml') || ct.contains('svg')) return _Kind.xml;
  if (ct.startsWith('text/') ||
      ct.contains('javascript') ||
      ct.contains('x-www-form-urlencoded')) {
    return _Kind.text;
  }
  if (r.body.isEmpty) return _Kind.text;
  // Unknown type: treat as text only if it decodes cleanly.
  try {
    final s = utf8.decode(
      r.body.length > 4096 ? r.body.sublist(0, 4096) : r.body,
    );
    final t = s.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) return _Kind.json;
    return s.contains('\u0000') ? _Kind.binary : _Kind.text;
  } on FormatException {
    return _Kind.binary;
  }
}

String _extFor(_Kind k, String? ct) {
  switch (k) {
    case _Kind.json:
      return 'json';
    case _Kind.xml:
      return 'xml';
    case _Kind.html:
      return 'html';
    case _Kind.text:
      return 'txt';
    case _Kind.image:
      final c = (ct ?? '').toLowerCase();
      if (c.contains('png')) return 'png';
      if (c.contains('jpeg') || c.contains('jpg')) return 'jpg';
      if (c.contains('gif')) return 'gif';
      if (c.contains('webp')) return 'webp';
      return 'img';
    case _Kind.media:
      final c = (ct ?? '').toLowerCase();
      final sub = c.contains('/')
          ? c.split('/')[1].split(';').first.trim()
          : '';
      if (sub == 'mpeg') return c.startsWith('audio') ? 'mp3' : 'mpg';
      if (sub == 'mp4' || sub == 'webm' || sub == 'ogg' || sub == 'wav') {
        return sub;
      }
      return 'media';
    case _Kind.binary:
      return 'bin';
  }
}

class ResponseInspector extends StatelessWidget {
  const ResponseInspector({super.key, required this.tab});

  final RequestTab tab;

  String _buildErrorText(BuildContext context, String code, String detail) {
    final key = 'err.build.$code';
    final s = context.t(key);
    final base = s == key ? code : s;
    return detail.isEmpty ? base : '$base ($detail)';
  }

  @override
  Widget build(BuildContext context) {
    if (tab.draft.kind != RequestKind.http) return StreamView(tab: tab);

    final o = tab.outcome;
    if (tab.phase == SendPhase.sending) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 12),
            Text(context.t('resp.sending'), style: context.secondary),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.read<WorkspaceCubit>().cancel(tab.id),
              child: Text(context.t('req.cancel')),
            ),
          ],
        ),
      );
    }
    if (o == null) {
      return EmptyState(
        icon: Icons.send_outlined,
        title: context.t('resp.emptyTitle'),
        message: context.t('resp.emptyMsg'),
      );
    }
    if (o.result == null &&
        o.failure == null &&
        o.buildError == null &&
        o.scriptError != null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          ErrorBanner(
            message: context.t('err.script.pre'),
            detail: o.scriptError!,
          ),
          if (o.scriptLogs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _ScriptLogs(logs: o.scriptLogs),
          ],
        ],
      );
    }
    if (o.buildError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: ErrorBanner(
          message: context.t('resp.buildFailed'),
          detail: _buildErrorText(
            context,
            o.buildError!.code,
            o.buildError!.detail,
          ),
        ),
      );
    }
    if (o.failure != null) {
      final f = o.failure!;
      final key = 'err.http.${f.kind.name}';
      return ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          ErrorBanner(message: context.t(key), detail: f.message),
          const SizedBox(height: 10),
          if (f.kind == HttpFailureKind.tls)
            InfoBanner(context.t('err.tlsHint'), warning: true),
          if (o.request != null) ...<Widget>[
            const SizedBox(height: 10),
            _RequestPreview(built: o),
          ],
        ],
      );
    }
    return _ResultView(
      key: ValueKey<Object>(o),
      outcome: o,
      previous: tab.previousBody,
    );
  }
}

class _ResultView extends StatefulWidget {
  const _ResultView({super.key, required this.outcome, this.previous});
  final ExecutionOutcome outcome;
  final String? previous;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _save(HttpResult r, _Kind kind) async {
    try {
      final name =
          'response-${DateTime.now().millisecondsSinceEpoch}.${_extFor(kind, r.contentType)}';
      final path = await context.read<FileService>().saveBytes(
        name,
        r.body,
        title: context.t('resp.save'),
      );
      if (path != null && mounted) {
        await showToast(
          context,
          context.t('resp.savedTo', <String>[fileNameOf(path)]),
        );
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        await showToast(
          context,
          context.t('resp.saveFailed', <String>[e.message]),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outcome;
    final r = o.result!;
    final c = context.colors;
    final fmt = _fmt(context);
    final kind = _classify(r);
    final passed =
        o.assertions.where((a) => a.passed).length +
        o.scriptTests.where((t) => t.passed).length;
    final totalChecks = o.assertions.length + o.scriptTests.length;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Wrap(
            spacing: 14,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                fmt.digits('${r.statusCode} ${r.reasonPhrase}'),
                style: context.statusStyle(r.statusCode),
              ),
              Text(fmt.duration(r.duration), style: context.timingStyle),
              Text(fmt.bytes(r.body.length), style: context.timingStyle),
              if (r.protocol == 'h2')
                Text('HTTP/2', style: context.timingStyle),
              if (r.redirects.isNotEmpty)
                Text(
                  context.t('resp.redirects', <String>[
                    fmt.integer(r.redirects.length),
                  ]),
                  style: context.timingStyle,
                ),
              if (r.truncated)
                Text(
                  context.t('resp.truncated'),
                  style: context.timingStyle.copyWith(color: c.warning),
                ),
              TextButton.icon(
                onPressed: () => _save(r, kind),
                icon: const Icon(Icons.download, size: 16),
                label: Text(context.t('resp.save')),
              ),
            ],
          ),
        ),
        PillTabBar(
          controller: _tabs,
          labels: <String>[
            context.t('resp.body'),
            '${context.t('resp.headers')} (${fmt.integer(r.headers.length)})',
            context.t('resp.cookies'),
            totalChecks == 0
                ? context.t('resp.tests')
                : '${context.t('resp.tests')} (${fmt.integer(passed)}/${fmt.integer(totalChecks)})',
            context.t('resp.request'),
            context.t('resp.timeline'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              _BodyView(result: r, kind: kind, previous: widget.previous),
              _HeadersView(headers: r.headers),
              _CookiesView(headers: r.headers),
              _TestsView(outcome: o),
              ListView(
                padding: const EdgeInsets.all(12),
                children: <Widget>[_RequestPreview(built: o)],
              ),
              TimelineView(result: r),
            ],
          ),
        ),
      ],
    );
  }

  Fmt _fmt(BuildContext context) {
    final s = context.watch<SettingsCubit>().state;
    return Fmt(persianDigits: s.persianDigits, jalali: s.jalaliDates);
  }
}

class _BodyView extends StatefulWidget {
  const _BodyView({required this.result, required this.kind, this.previous});
  final HttpResult result;
  final _Kind kind;
  final String? previous;

  @override
  State<_BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<_BodyView> {
  static const int _editorLimit = 400000;
  bool _raw = false;
  bool _diff = false;
  bool _tree = false;
  bool _page = false;
  final CodeEditorController _ctl = CodeEditorController();
  final TextEditingController _search = TextEditingController();
  late String _text;
  late String _pretty;

  @override
  void initState() {
    super.initState();
    // HTML opens as a rendered page; Source and Raw are one click away.
    _page = widget.kind == _Kind.html;
    _prepare();
  }

  void _prepare() {
    final r = widget.result;
    if (widget.kind == _Kind.image ||
        widget.kind == _Kind.binary ||
        widget.kind == _Kind.media) {
      _text = '';
      _pretty = '';
      return;
    }
    _text = utf8.decode(r.body, allowMalformed: true);
    _pretty = _text;
    if (widget.kind == _Kind.json && _text.length < 2000000) {
      _pretty = formatJson(_text) ?? _text;
    }
    _applyShown();
  }

  /// Loads the visible text into the editor outside of build().
  void _applyShown() {
    final shown = _raw ? _text : _pretty;
    if (shown.length <= _editorLimit) {
      _ctl.value = TextEditingValue(text: shown);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _search.dispose();
    super.dispose();
  }

  CodeLanguage get _lang {
    switch (widget.kind) {
      case _Kind.json:
        return CodeLanguage.json;
      case _Kind.xml:
      case _Kind.html:
        return CodeLanguage.xml;
      default:
        return CodeLanguage.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final c = context.colors;
    final fmt = Fmt(
      persianDigits: context.watch<SettingsCubit>().state.persianDigits,
    );

    if (widget.kind == _Kind.image) {
      return InteractiveViewer(
        child: Center(
          child: Image.memory(
            r.body,
            fit: BoxFit.contain,
            errorBuilder: (ctx, e, st) =>
                Text(ctx.t('resp.imageFailed'), style: ctx.errorText),
          ),
        ),
      );
    }
    if (widget.kind == _Kind.media) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          InfoBanner(
            context.t('resp.media', <String>[
              r.contentType ?? '',
              fmt.bytes(r.body.length),
            ]),
          ),
        ],
      );
    }
    if (widget.kind == _Kind.binary) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          InfoBanner(
            context.t('resp.binary', <String>[fmt.bytes(r.body.length)]),
          ),
          const SizedBox(height: 10),
          SelectableText(
            _hexPreview(r.body),
            style: context.mono.copyWith(fontSize: 12),
          ),
        ],
      );
    }
    if (r.body.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: context.t('resp.emptyBody'),
      );
    }

    final shown = _raw ? _text : _pretty;
    final big = shown.length > _editorLimit;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: <Widget>[
              SegmentedButton<int>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: <ButtonSegment<int>>[
                  if (widget.kind == _Kind.html)
                    ButtonSegment<int>(
                      value: 4,
                      label: Text(context.t('resp.page')),
                    ),
                  ButtonSegment<int>(
                    value: 0,
                    label: Text(context.t('resp.pretty')),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text(context.t('resp.raw')),
                  ),
                  if (widget.kind == _Kind.json && _text.length < 2000000)
                    ButtonSegment<int>(
                      value: 3,
                      label: Text(context.t('resp.tree')),
                    ),
                  if (widget.previous != null)
                    ButtonSegment<int>(
                      value: 2,
                      label: Text(context.t('resp.diff')),
                    ),
                ],
                selected: <int>{
                  _page ? 4 : (_tree ? 3 : (_diff ? 2 : (_raw ? 1 : 0))),
                },
                onSelectionChanged: (s) {
                  setState(() {
                    _page = s.first == 4;
                    _tree = s.first == 3;
                    _diff = s.first == 2;
                    _raw = s.first == 1;
                  });
                  _applyShown();
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: context.t('common.copy'),
                icon: Icon(Icons.copy, size: 18, color: c.textSecondary),
                onPressed: () => copyText(context, shown),
              ),
            ],
          ),
        ),
        if (big)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Column(
              children: <Widget>[
                InfoBanner(
                  context.t('resp.largeMode', <String>[
                    fmt.bytes(shown.length),
                  ]),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: context.t('editor.find'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: _page
                ? HtmlBrowserView(html: _text, url: r.finalUrl)
                : _tree
                ? JsonTreeView(text: _text)
                : _diff
                ? _DiffView(
                    before: _prettyOf(widget.previous ?? ''),
                    after: _pretty,
                  )
                : (big
                      ? LinesView(text: shown, query: _search.text)
                      : SettingsCodeEditor(
                          controller: _ctl,
                          language: _lang,
                          readOnly: true,
                        )),
          ),
        ),
      ],
    );
  }

  String _prettyOf(String text) {
    if (widget.kind == _Kind.json && text.length < 2000000) {
      return formatJson(text) ?? text;
    }
    return text;
  }

  String _hexPreview(Uint8List b) {
    final n = math.min(b.length, 512);
    final buf = StringBuffer();
    for (var i = 0; i < n; i += 16) {
      final end = math.min(i + 16, n);
      final bytes = b.sublist(i, end);
      final hex = bytes
          .map((x) => x.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final ascii = String.fromCharCodes(
        bytes.map((x) => x >= 32 && x < 127 ? x : 46),
      );
      buf.writeln(
        '${i.toRadixString(16).padLeft(6, '0')}  ${hex.padRight(47)}  $ascii',
      );
    }
    return buf.toString();
  }
}

class _DiffView extends StatelessWidget {
  const _DiffView({required this.before, required this.after});
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = before.split('\n');
    final b = after.split('\n');
    final diff = (a.length > 5000 || b.length > 5000) ? null : lineDiff(a, b);
    if (diff == null) {
      return Center(
        child: Text(context.t('resp.diffTooLarge'), style: context.secondary),
      );
    }
    final changed = diff.where((l) => l.op != DiffOp.same).length;
    if (changed == 0) {
      return Center(
        child: Text(context.t('resp.diffNone'), style: context.secondary),
      );
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.t('resp.diffInfo', <String>['$changed']),
              style: context.secondary,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: diff.length,
            itemBuilder: (ctx, i) {
              final l = diff[i];
              final color = l.op == DiffOp.added
                  ? c.success
                  : (l.op == DiffOp.removed ? c.danger : null);
              return Container(
                color: color?.withAlpha(28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${l.op == DiffOp.added ? '+' : (l.op == DiffOp.removed ? '-' : ' ')} ${l.text}',
                  style: ctx.mono.copyWith(
                    fontSize: 12.5,
                    color: color ?? c.textPrimary,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeadersView extends StatelessWidget {
  const _HeadersView({required this.headers});
  final Map<String, List<String>> headers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keys = headers.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (keys.isEmpty) {
      return EmptyState(
        icon: Icons.list_alt,
        title: context.t('resp.noHeaders'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, _) => Divider(color: c.border, height: 12),
      itemBuilder: (ctx, i) {
        final k = keys[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              k,
              style: ctx.mono.copyWith(
                fontWeight: FontWeight.w600,
                color: c.synKey,
              ),
            ),
            for (final v in headers[k]!) SelectableText(v, style: ctx.mono),
          ],
        );
      },
    );
  }
}

class _Cookie {
  _Cookie(this.name, this.value, this.attrs);
  final String name;
  final String value;
  final List<String> attrs;
}

List<_Cookie> _parseCookies(Map<String, List<String>> headers) {
  final out = <_Cookie>[];
  for (final e in headers.entries) {
    if (e.key.toLowerCase() != 'set-cookie') continue;
    for (final line in e.value) {
      final parts = line
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      final eq = parts.first.indexOf('=');
      out.add(
        _Cookie(
          eq < 0 ? parts.first : parts.first.substring(0, eq),
          eq < 0 ? '' : parts.first.substring(eq + 1),
          parts.skip(1).toList(),
        ),
      );
    }
  }
  return out;
}

class _CookiesView extends StatefulWidget {
  const _CookiesView({required this.headers});
  final Map<String, List<String>> headers;

  @override
  State<_CookiesView> createState() => _CookiesViewState();
}

class _CookiesViewState extends State<_CookiesView> {
  final Set<int> _revealed = <int>{};

  @override
  Widget build(BuildContext context) {
    final cookies = _parseCookies(widget.headers);
    final c = context.colors;
    if (cookies.isEmpty) {
      return EmptyState(
        icon: Icons.cookie_outlined,
        title: context.t('resp.noCookies'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        InfoBanner(context.t('resp.cookiesNote')),
        const SizedBox(height: 10),
        for (var i = 0; i < cookies.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        cookies[i].name,
                        style: context.mono.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        if (!_revealed.remove(i)) _revealed.add(i);
                      }),
                      child: Text(
                        context.t(
                          _revealed.contains(i) ? 'resp.hide' : 'resp.reveal',
                        ),
                      ),
                    ),
                  ],
                ),
                SelectableText(
                  _revealed.contains(i) ? cookies[i].value : Redactor.mask,
                  style: context.mono,
                ),
                if (cookies[i].attrs.isNotEmpty)
                  Text(
                    cookies[i].attrs.join('  ·  '),
                    style: context.secondary.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TestsView extends StatelessWidget {
  const _TestsView({required this.outcome});
  final ExecutionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (outcome.assertions.isEmpty &&
        outcome.extracted.isEmpty &&
        outcome.scriptTests.isEmpty &&
        outcome.scriptLogs.isEmpty &&
        outcome.scriptError == null) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        title: context.t('resp.noTests'),
        message: context.t('resp.noTestsMsg'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        if (outcome.scriptError != null) ...<Widget>[
          ErrorBanner(
            message: context.t('err.script.post'),
            detail: outcome.scriptError!,
          ),
          const SizedBox(height: 10),
        ],
        for (final t in outcome.scriptTests)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Icon(
                  t.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 18,
                  color: t.passed ? c.success : c.danger,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(t.name, style: context.body)),
              ],
            ),
          ),
        if (outcome.scriptLogs.isNotEmpty) ...<Widget>[
          _ScriptLogs(logs: outcome.scriptLogs),
          const SizedBox(height: 8),
        ],
        for (final a in outcome.assertions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  a.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 18,
                  color: a.passed ? c.success : c.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('tests.kind.${a.assertion.kind.name}'),
                        style: context.body,
                      ),
                      Text(a.message, style: context.secondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (outcome.extracted.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(context.t('resp.extracted'), style: context.sectionHeading),
          const SizedBox(height: 4),
          for (final k in outcome.extracted.keys)
            Text('{{$k}}', style: context.mono.copyWith(color: c.synVariable)),
        ],
      ],
    );
  }
}

class _RequestPreview extends StatelessWidget {
  const _RequestPreview({required this.built});
  final ExecutionOutcome built;

  @override
  Widget build(BuildContext context) {
    final b = built.request;
    if (b == null) return const SizedBox.shrink();
    final pv = b.preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InfoBanner(context.t('resp.previewNote')),
        const SizedBox(height: 10),
        SelectableText(
          '${pv.method} ${pv.url}',
          style: context.mono.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final h in pv.headers)
          SelectableText(
            '${h.key}: ${h.value}',
            style: context.mono.copyWith(fontSize: 12),
          ),
        if (pv.bodyPreview.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SelectableText(
            pv.bodyPreview,
            style: context.mono.copyWith(fontSize: 12),
          ),
        ],
        for (final w in b.warnings) ...<Widget>[
          const SizedBox(height: 8),
          InfoBanner(context.t('warn.$w'), warning: true),
        ],
      ],
    );
  }
}

class _ScriptLogs extends StatelessWidget {
  const _ScriptLogs({required this.logs});
  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.t('resp.scriptLog'), style: context.sectionHeading),
        const SizedBox(height: 4),
        for (final l in logs)
          SelectableText(l, style: context.mono.copyWith(fontSize: 12)),
      ],
    );
  }
}
