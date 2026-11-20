import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/platform/file_service.dart';
import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/collections/domain/collection_models.dart';
import '../../features/environments/application/environments_cubit.dart';
import '../../features/environments/domain/variables.dart';
import '../../features/import_export/curl.dart';
import '../../features/import_export/openapi.dart';
import '../../features/import_export/postbox_format.dart';
import '../../features/import_export/postman.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';
import '../../core/util/format.dart';

enum _Format { auto, curl, postman, postbox, openapi }

class ImportExportPage extends StatelessWidget {
  const ImportExportPage({
    super.key,
    this.initialCollectionId,
    this.initialImportText,
    this.initialSelection,
  });

  /// Pre-selects a collection on the export tab.
  final String? initialCollectionId;

  /// Text to preview on the import tab (dropped file, shared text). Nothing is
  /// imported until the user confirms the preview.
  final String? initialImportText;

  /// Node ids to export (bulk export from the sidebar selection).
  final Set<String>? initialSelection;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: (initialCollectionId == null && initialSelection == null)
          ? 0
          : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t('ie.title')),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: context.t('ie.import')),
              Tab(text: context.t('ie.export')),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: <Widget>[
            _ImportTab(initialText: initialImportText),
            _ExportTab(
              initialCollectionId: initialCollectionId,
              selection: initialSelection,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportTab extends StatefulWidget {
  const _ImportTab({this.initialText});
  final String? initialText;

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _path = TextEditingController();
  _Format _format = _Format.auto;
  ImportPlan? _plan;
  CurlImport? _curl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = widget.initialText;
    if (t != null && t.trim().isNotEmpty) {
      _text.text = t.length > kMaxImportBytes ? '' : t;
      // Show the preview straight away; importing still needs a click.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _preview();
      });
    }
  }

  Future<void> _browse() async {
    final files = context.read<FileService>();
    final picked = await files.pickFile(
      extensions: <String>['json', 'txt', 'sh', 'yaml', 'yml'],
    );
    if (picked == null) return;
    _path.text = picked.path;
    await _loadFile();
  }

  @override
  void dispose() {
    _text.dispose();
    _path.dispose();
    super.dispose();
  }

  _Format _detect(String t) {
    final s = t.trimLeft();
    if (s.startsWith('curl')) return _Format.curl;
    try {
      final j = jsonDecode(s);
      if (j is Map) {
        if (j['format'] == 'postbox') return _Format.postbox;
        if (j.containsKey('openapi')) return _Format.openapi;
        if (j.containsKey('info') && j.containsKey('item')) {
          return _Format.postman;
        }
      }
    } on FormatException {
      // fall through
    }
    return _Format.postman;
  }

  Future<void> _loadFile() async {
    final path = _path.text.trim();
    if (path.isEmpty) return;
    try {
      final content = await context.read<FileService>().readText(
        path,
        maxBytes: kMaxImportBytes,
      );
      setState(() {
        _text.text = content;
        _plan = null;
        _curl = null;
      });
    } on FileTooLargeException {
      if (mounted) await showToast(context, context.t('ie.tooLarge'));
    } on FileSystemException catch (e) {
      if (mounted) {
        await showToast(
          context,
          context.t('ie.fileError', <String>[e.message]),
        );
      }
    }
  }

  void _preview() {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    final f = _format == _Format.auto ? _detect(t) : _format;
    setState(() {
      _plan = null;
      _curl = null;
      switch (f) {
        case _Format.curl:
          _curl = parseCurl(t);
        case _Format.postman:
          _plan = parsePostmanCollection(t);
        case _Format.postbox:
          _plan = parsePostBox(t);
        case _Format.openapi:
          _plan = parseOpenApi(t);
        case _Format.auto:
          break;
      }
    });
  }

  Future<void> _commit() async {
    final plan = _plan;
    if (plan == null || plan.hasErrors) return;
    setState(() => _busy = true);
    try {
      final collections = context.read<CollectionsCubit>();
      final envs = context.read<EnvironmentsCubit>();
      final n = await collections.commitImport(plan);
      for (final e in plan.environments) {
        await envs.save(e);
      }
      if (!mounted) return;
      await showToast(context, context.t('ie.imported', <String>['$n']));
      setState(() {
        _plan = null;
        _text.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _notes(List<ImportNote> notes) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  n.level == NoteLevel.error
                      ? Icons.error_outline
                      : (n.level == NoteLevel.warning
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline),
                  size: 16,
                  color: n.level == NoteLevel.error
                      ? c.danger
                      : (n.level == NoteLevel.warning
                            ? c.warning
                            : c.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(n.message, style: context.body)),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _tree(List<ImportedNode> nodes, int depth, int budget) {
    final out = <Widget>[];
    var left = budget;
    for (final n in nodes) {
      if (left-- <= 0) {
        out.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 14.0),
            child: Text('…', style: context.secondary),
          ),
        );
        break;
      }
      if (n.isFolder) {
        out.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 14.0, bottom: 2),
            child: Row(
              children: <Widget>[
                const Icon(Icons.folder_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(n.name, style: context.body)),
              ],
            ),
          ),
        );
        out.addAll(_tree(n.children, depth + 1, left));
      } else {
        out.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 14.0, bottom: 2),
            child: Row(
              children: <Widget>[
                MethodBadge(n.request!.method, width: 50),
                Expanded(
                  child: Text(
                    n.request!.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: context.body,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final curl = _curl;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        InfoBanner(context.t('ie.importInfo')),
        const SizedBox(height: 12),
        DropdownButtonFormField<_Format>(
          initialValue: _format,
          decoration: InputDecoration(labelText: context.t('ie.format')),
          items: <DropdownMenuItem<_Format>>[
            DropdownMenuItem<_Format>(
              value: _Format.auto,
              child: Text(context.t('ie.auto')),
            ),
            const DropdownMenuItem<_Format>(
              value: _Format.curl,
              child: Text('cURL'),
            ),
            const DropdownMenuItem<_Format>(
              value: _Format.postman,
              child: Text('Postman Collection v2.1'),
            ),
            const DropdownMenuItem<_Format>(
              value: _Format.postbox,
              child: Text('PostBox (.json)'),
            ),
            DropdownMenuItem<_Format>(
              value: _Format.openapi,
              child: Text(context.t('ie.openapiJson')),
            ),
          ],
          onChanged: (v) => setState(() => _format = v ?? _Format.auto),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _path,
                style: context.mono,
                decoration: InputDecoration(
                  labelText: context.t('ie.filePath'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _browse,
              child: Text(context.t('ie.browse')),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _loadFile,
              child: Text(context.t('ie.load')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 14,
          style: context.mono.copyWith(fontSize: 12.5),
          decoration: InputDecoration(
            labelText: context.t('ie.paste'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: _preview,
            child: Text(context.t('ie.preview')),
          ),
        ),
        if (curl != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(context.t('ie.previewTitle'), style: context.sectionHeading),
          const SizedBox(height: 8),
          _notes(curl.notes),
          if (curl.request != null) ...<Widget>[
            Row(
              children: <Widget>[
                MethodBadge(curl.request!.method),
                Expanded(
                  child: SelectableText(curl.request!.url, style: context.mono),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                context.read<WorkspaceCubit>().newTab(model: curl.request);
                Navigator.of(context).maybePop();
              },
              child: Text(context.t('ie.openAsRequest')),
            ),
          ],
        ],
        if (plan != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(context.t('ie.previewTitle'), style: context.sectionHeading),
          const SizedBox(height: 8),
          _notes(plan.notes),
          for (final col in plan.collections) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '${col.name}  ·  ${context.t('ie.requests', <String>['${col.requestCount}'])}  ·  ${context.t('ie.vars', <String>['${col.variables.length}'])}',
              style: context.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ..._tree(col.nodes, 0, 40),
          ],
          if (plan.environments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.t('ie.envs', <String>['${plan.environments.length}']),
                style: context.body,
              ),
            ),
          const SizedBox(height: 14),
          if (!plan.hasErrors)
            FilledButton(
              onPressed: _busy ? null : _commit,
              child: Text(
                context.t('ie.importNow', <String>['${plan.requestCount}']),
              ),
            ),
        ],
      ],
    );
  }
}

enum _ExportKind { postbox, postman, curl }

class _ExportTab extends StatefulWidget {
  const _ExportTab({this.initialCollectionId, this.selection});
  final String? initialCollectionId;

  /// Selected sidebar nodes; when set, exports offer "selected items".
  final Set<String>? selection;

  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  _ExportKind _kind = _ExportKind.postbox;
  String? _collectionId;
  bool _secrets = false;
  bool _envs = true;
  bool _useSelection = false;
  String _output = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _useSelection = (widget.selection ?? const <String>{}).isNotEmpty;
    final cols = context.read<CollectionsCubit>().state.collections;
    _collectionId = cols.any((c) => c.id == widget.initialCollectionId)
        ? widget.initialCollectionId
        : (cols.isEmpty ? null : cols.first.id);
  }

  Future<ImportedCollection?> _tree(CollectionsCubit collections) async {
    if (_useSelection) {
      return collections.buildSelectionExport(
        widget.selection!,
        includeSecrets: _secrets,
      );
    }
    if (_collectionId == null) return null;
    return collections.buildExportTree(
      _collectionId!,
      includeSecrets: _secrets,
    );
  }

  Future<void> _generate() async {
    setState(() {
      _error = null;
      _output = '';
    });
    final collections = context.read<CollectionsCubit>();
    final envs = context.read<EnvironmentsCubit>().state;
    try {
      switch (_kind) {
        case _ExportKind.curl:
          final tab = context.read<WorkspaceCubit>().state.active;
          if (tab == null) return;
          setState(
            () => _output = exportCurl(tab.draft, includeSecrets: _secrets),
          );
        case _ExportKind.postman:
          final tree = await _tree(collections);
          if (tree == null) return;
          setState(
            () => _output = prettyJson(
              exportPostmanCollection(tree, includeSecrets: _secrets),
            ),
          );
        case _ExportKind.postbox:
          final tree = await _tree(collections);
          if (tree == null) return;
          setState(
            () => _output = prettyJson(
              exportPostBox(
                collections: <ImportedCollection>[tree],
                environments: _envs ? envs.environments : const <Environment>[],
                includeSecrets: _secrets,
              ),
            ),
          );
      }
    } on Exception catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _saveFile() async {
    try {
      final ext = _kind == _ExportKind.curl ? 'sh' : 'json';
      final name =
          'postbox-export-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = await context.read<FileService>().saveText(
        name,
        _output,
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
    final cols = context.watch<CollectionsCubit>().state.collections;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        InfoBanner(context.t('ie.exportInfo')),
        const SizedBox(height: 12),
        DropdownButtonFormField<_ExportKind>(
          initialValue: _kind,
          decoration: InputDecoration(labelText: context.t('ie.format')),
          items: <DropdownMenuItem<_ExportKind>>[
            const DropdownMenuItem<_ExportKind>(
              value: _ExportKind.postbox,
              child: Text('PostBox (.json)'),
            ),
            const DropdownMenuItem<_ExportKind>(
              value: _ExportKind.postman,
              child: Text('Postman Collection v2.1'),
            ),
            DropdownMenuItem<_ExportKind>(
              value: _ExportKind.curl,
              child: Text(context.t('ie.curlCurrent')),
            ),
          ],
          onChanged: (v) => setState(() {
            _kind = v ?? _ExportKind.postbox;
            _output = '';
          }),
        ),
        if (_kind != _ExportKind.curl &&
            (widget.selection ?? const <String>{}).isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.t('ie.selectedOnly', <String>[
                '${widget.selection!.length}',
              ]),
            ),
            value: _useSelection,
            onChanged: (v) => setState(() {
              _useSelection = v;
              _output = '';
            }),
          ),
        if (_kind != _ExportKind.curl && !_useSelection) ...<Widget>[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey<String?>(_collectionId),
            initialValue: _collectionId,
            decoration: InputDecoration(
              labelText: context.t('save.collection'),
            ),
            items: <DropdownMenuItem<String>>[
              for (final c in cols)
                DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _collectionId = v),
          ),
        ],
        if (_kind == _ExportKind.postbox)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('ie.includeEnvs')),
            value: _envs,
            onChanged: (v) => setState(() => _envs = v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('ie.includeSecrets')),
          subtitle: Text(
            context.t('ie.includeSecretsHelp'),
            style: context.secondary,
          ),
          value: _secrets,
          onChanged: (v) => setState(() => _secrets = v),
        ),
        if (_secrets) InfoBanner(context.t('ie.secretsWarning'), warning: true),
        if (_kind == _ExportKind.postman)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InfoBanner(context.t('ie.postmanLossy')),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed:
                (_kind != _ExportKind.curl &&
                    !_useSelection &&
                    _collectionId == null)
                ? null
                : _generate,
            child: Text(context.t('ie.generate')),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 10),
          ErrorBanner(message: _error!),
        ],
        if (_output.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: () => copyText(context, _output),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(context.t('common.copy')),
              ),
              TextButton.icon(
                onPressed: _saveFile,
                icon: const Icon(Icons.download, size: 16),
                label: Text(context.t('resp.save')),
              ),
            ],
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _output,
                style: context.mono.copyWith(fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
