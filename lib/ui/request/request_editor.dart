import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/collections/domain/node_settings.dart';
import '../../features/import_export/curl.dart';
import '../../features/requests/domain/request_models.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../editor/code_editor_controller.dart';
import '../editor/highlighter.dart';
import 'save_actions.dart';
import '../widgets/common.dart';
import '../widgets/key_value_editor.dart';
import '../templates/templates_sheet.dart';
import '../widgets/soft.dart';
import 'auth_editor.dart';
import 'body_editor.dart';
import 'scripts_editor.dart';
import 'tests_editor.dart';
import 'variables_editor.dart';

/// Editor for one request tab. Create it with a key per tab id so controllers
/// are not shared between tabs.
class RequestEditor extends StatefulWidget {
  const RequestEditor({
    super.key,
    required this.tab,
    this.compact = false,
    this.onSent,
  });

  final RequestTab tab;

  /// Phone layout: the URL bar wraps onto two rows.
  final bool compact;

  /// Called after Send is pressed (the phone layout uses it to show the response).
  final VoidCallback? onSent;

  @override
  State<RequestEditor> createState() => _RequestEditorState();
}

class _RequestEditorState extends State<RequestEditor>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this);
  late final CodeEditorController _url = CodeEditorController(
    text: widget.tab.draft.url,
    language: CodeLanguage.text,
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.tab.draft.name,
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.tab.draft.description,
  );

  @override
  void initState() {
    super.initState();
    _url.addListener(() {
      if (_url.text != _draft.url) _update(_draft.copyWith(url: _url.text));
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _url.dispose();
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  RequestModel get _draft => widget.tab.draft;
  WorkspaceCubit get _cubit => context.read<WorkspaceCubit>();

  void _update(RequestModel r) => _cubit.update(widget.tab.id, r);

  Future<void> _customMethod() async {
    final m = await promptText(
      context,
      title: context.t('req.customMethod'),
      label: context.t('req.method'),
    );
    if (m == null) return;
    final clean = m.trim().toUpperCase();
    if (RegExp(r'^[A-Z][A-Z0-9\-]*$').hasMatch(clean)) {
      _update(_draft.copyWith(method: clean));
    } else if (mounted) {
      await showToast(context, context.t('req.invalidMethod'));
    }
  }

  Future<void> _save({bool saveAs = false}) =>
      saveTab(context, widget.tab, saveAs: saveAs);

  void _send() {
    final tab = widget.tab;
    if (tab.phase == SendPhase.sending) {
      _cubit.cancel(tab.id);
    } else if (tab.streaming) {
      _cubit.disconnect(tab.id);
    } else {
      _cubit.send(tab.id);
      widget.onSent?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final r = tab.draft;
    final c = context.colors;
    final isHttp = r.kind == RequestKind.http;
    final busy = tab.phase == SendPhase.sending;

    final methodBtn = isHttp
        ? PopupMenuButton<String>(
            tooltip: context.t('req.method'),
            onSelected: (m) {
              if (m == '*') {
                _customMethod();
              } else {
                _update(r.copyWith(method: m));
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              for (final m in kHttpMethods)
                PopupMenuItem<String>(
                  value: m,
                  child: MethodBadge(m, width: 70),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: '*',
                child: Text(context.t('req.custom')),
              ),
            ],
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  MethodBadge(r.method, width: 52),
                  Icon(Icons.arrow_drop_down, size: 18, color: c.textSecondary),
                ],
              ),
            ),
          )
        : Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              r.kind == RequestKind.sse ? 'SSE' : 'WS',
              style: context.methodBadge.copyWith(color: c.accent),
            ),
          );

    final urlField = SizedBox(
      height: 44,
      child: TextField(
        controller: _url,
        style: context.urlStyle,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          hintText: r.kind == RequestKind.websocket
              ? 'wss://echo.example.com'
              : 'https://api.example.com/v1/users',
        ),
        onSubmitted: (_) => _send(),
      ),
    );

    final String sendLabel;
    if (busy) {
      sendLabel = context.t('req.cancel');
    } else if (r.kind == RequestKind.http) {
      sendLabel = context.t('req.send');
    } else {
      sendLabel = tab.streaming
          ? context.t('req.disconnect')
          : context.t('req.connect');
    }
    final sendBtn = SizedBox(
      height: 44,
      child: FilledButton.icon(
        style: busy || tab.streaming
            ? FilledButton.styleFrom(
                backgroundColor: c.danger,
                foregroundColor: Theme.of(context).colorScheme.onError,
              )
            : null,
        onPressed: _send,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(busy || tab.streaming ? Icons.stop : Icons.send, size: 18),
        label: Text(sendLabel),
      ),
    );

    final saveBtn = IconButton(
      tooltip: context.t('common.save'),
      icon: Icon(
        Icons.save_outlined,
        color: tab.dirty ? c.accent : c.textSecondary,
      ),
      onPressed: _save,
    );
    final menu = PopupMenuButton<String>(
      tooltip: context.t('common.more'),
      icon: Icon(Icons.more_vert, color: c.textSecondary),
      onSelected: (v) async {
        switch (v) {
          case 'saveAs':
            await _save(saveAs: true);
          case 'dup':
            await _cubit.duplicateTab(tab.id);
          case 'curl':
            await copyText(
              context,
              exportCurl(r),
              toast: context.t('req.curlCopied'),
            );
          case 'tpl':
            await saveAsTemplate(context, r);
          case 'http':
            _update(r.copyWith(kind: RequestKind.http));
          case 'sse':
            _update(r.copyWith(kind: RequestKind.sse, method: 'GET'));
          case 'ws':
            _update(r.copyWith(kind: RequestKind.websocket, method: 'GET'));
        }
      },
      itemBuilder: (ctx) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'saveAs',
          child: Text(ctx.t('req.saveAs')),
        ),
        PopupMenuItem<String>(
          value: 'dup',
          child: Text(ctx.t('req.duplicate')),
        ),
        PopupMenuItem<String>(
          value: 'curl',
          child: Text(ctx.t('req.copyCurl')),
        ),
        PopupMenuItem<String>(value: 'tpl', child: Text(ctx.t('tpl.saveAs'))),
        const PopupMenuDivider(),
        PopupMenuItem<String>(value: 'http', child: Text('HTTP')),
        PopupMenuItem<String>(value: 'sse', child: Text(ctx.t('req.protoSse'))),
        PopupMenuItem<String>(value: 'ws', child: Text(ctx.t('req.protoWs'))),
      ],
    );

    // Unresolved variable warning across the editable text fields.
    final resolver = _cubit.resolverFor(tab);
    final unresolved = <String>{
      ...resolver.findUnresolved(r.url),
      for (final h in r.headers.where((h) => h.enabled))
        ...resolver.findUnresolved('${h.key}${h.value}'),
      for (final p in r.params.where((p) => p.enabled))
        ...resolver.findUnresolved('${p.key}${p.value}'),
      ...resolver.findUnresolved(r.body),
    };

    final enabledParams = r.params
        .where((p) => p.enabled && p.key.isNotEmpty)
        .length;
    final enabledHeaders = r.headers
        .where((p) => p.enabled && p.key.isNotEmpty)
        .length;

    String label(String key, int n) =>
        n > 0 ? '${context.t(key)} ($n)' : context.t(key);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: widget.compact
              ? Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        methodBtn,
                        const SizedBox(width: 6),
                        Expanded(child: urlField),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(child: sendBtn),
                        saveBtn,
                        menu,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    methodBtn,
                    const SizedBox(width: 6),
                    Expanded(child: urlField),
                    const SizedBox(width: 8),
                    sendBtn,
                    const SizedBox(width: 4),
                    saveBtn,
                    menu,
                  ],
                ),
        ),
        if (unresolved.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: InfoBanner(
              context.t('req.unresolved', <String>[
                unresolved.map((e) => '{{$e}}').join(', '),
              ]),
              warning: true,
            ),
          ),
        PillTabBar(
          controller: _tabs,
          labels: <String>[
            label('req.params', enabledParams),
            label('req.headers', enabledHeaders),
            context.t(isHttp ? 'req.body' : 'req.bodyNA'),
            context.t('req.auth'),
            label('req.vars', r.variables.length),
            (r.preScript.trim().isNotEmpty || r.postScript.trim().isNotEmpty)
                ? '${context.t('req.scripts')} •'
                : context.t('req.scripts'),
            label('req.tests', r.assertions.length + r.extractions.length),
            context.t('req.info'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              KeyValueEditor(
                items: r.params,
                bulkSeparator: '=',
                onChanged: (v) => _update(r.copyWith(params: v)),
              ),
              KeyValueEditor(
                items: r.headers,
                keyHint: 'Header',
                bulkSeparator: ':',
                onChanged: (v) => _update(r.copyWith(headers: v)),
              ),
              BodyEditor(request: r, onChanged: _update),
              _InheritedAuthEditor(
                tab: tab,
                onChanged: (a) => _update(r.copyWith(auth: a)),
              ),
              VariablesEditor(
                request: r,
                resolver: resolver,
                onChanged: (v) => _update(r.copyWith(variables: v)),
              ),
              ScriptsEditor(
                pre: r.preScript,
                post: r.postScript,
                onChanged: (pre, post) =>
                    _update(r.copyWith(preScript: pre, postScript: post)),
              ),
              TestsEditor(
                assertions: r.assertions,
                extractions: r.extractions,
                onAssertions: (v) => _update(r.copyWith(assertions: v)),
                onExtractions: (v) => _update(r.copyWith(extractions: v)),
              ),
              ListView(
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: context.t('common.name'),
                    ),
                    onChanged: (v) => _update(r.copyWith(name: v)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _desc,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: context.t('common.description'),
                    ),
                    onChanged: (v) => _update(r.copyWith(description: v)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Auth editor for a request: explains which folder or collection an
/// inherited auth comes from.
class _InheritedAuthEditor extends StatelessWidget {
  const _InheritedAuthEditor({required this.tab, required this.onChanged});

  final RequestTab tab;
  final ValueChanged<AuthConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final auth = tab.draft.auth;
    if (auth.type != AuthType.inherit) {
      return AuthEditor(auth: auth, onChanged: onChanged);
    }
    return FutureBuilder<EffectiveContext>(
      future: context.read<WorkspaceCubit>().inheritedFor(tab),
      builder: (context, snap) {
        final ctx = snap.data;
        final String hint;
        if (ctx?.auth == null || ctx!.auth!.type == AuthType.none) {
          hint = context.t('auth.inheritNone');
        } else {
          hint = context.t('auth.inheritFrom', <String>[
            ctx.authSource ?? '',
            context.t('auth.${ctx.auth!.type.name}'),
          ]);
        }
        return AuthEditor(auth: auth, onChanged: onChanged, inheritHint: hint);
      },
    );
  }
}
