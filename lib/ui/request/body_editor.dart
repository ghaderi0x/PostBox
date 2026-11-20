import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/platform/file_service.dart';
import '../../core/design/typography.dart';
import '../../features/requests/domain/request_models.dart';
import '../../l10n/strings.dart';
import '../editor/code_editor_controller.dart';
import '../editor/highlighter.dart';
import '../editor/settings_code_editor.dart';
import '../widgets/common.dart';
import '../widgets/key_value_editor.dart';
import '../../core/util/format.dart';

class BodyEditor extends StatefulWidget {
  const BodyEditor({super.key, required this.request, required this.onChanged});

  final RequestModel request;
  final ValueChanged<RequestModel> onChanged;

  @override
  State<BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<BodyEditor> {
  late final CodeEditorController _body;
  late final CodeEditorController _aux;
  late final TextEditingController _contentType;
  late final TextEditingController _binaryPath;

  @override
  void initState() {
    super.initState();
    _body = CodeEditorController(text: widget.request.body);
    _aux = CodeEditorController(text: widget.request.bodyAux);
    _contentType = TextEditingController(text: widget.request.bodyAux);
    _binaryPath = TextEditingController(
      text: widget.request.bodyType == BodyType.binary
          ? widget.request.body
          : '',
    );
    _body.addListener(_onBody);
    _aux.addListener(_onAux);
  }

  @override
  void dispose() {
    _body.dispose();
    _aux.dispose();
    _contentType.dispose();
    _binaryPath.dispose();
    super.dispose();
  }

  void _onBody() {
    if (_body.text != widget.request.body) {
      widget.onChanged(widget.request.copyWith(body: _body.text));
    }
  }

  void _onAux() {
    if (widget.request.bodyType == BodyType.graphql &&
        _aux.text != widget.request.bodyAux) {
      widget.onChanged(widget.request.copyWith(bodyAux: _aux.text));
    }
  }

  static const Map<BodyType, String> _labels = <BodyType, String>{
    BodyType.none: 'body.none',
    BodyType.json: 'body.json',
    BodyType.text: 'body.text',
    BodyType.formUrlEncoded: 'body.form',
    BodyType.multipart: 'body.multipart',
    BodyType.raw: 'body.raw',
    BodyType.graphql: 'body.graphql',
    BodyType.binary: 'body.binary',
  };

  void _setType(BodyType t) {
    // The raw type reuses bodyAux for Content-Type, GraphQL for variables.
    final aux = t == BodyType.raw
        ? _contentType.text
        : (t == BodyType.graphql ? _aux.text : widget.request.bodyAux);
    // `body` holds a file path for binary bodies and text otherwise, so it is
    // cleared when crossing that line instead of showing a path as JSON.
    final was = widget.request.bodyType;
    var body = widget.request.body;
    if ((t == BodyType.binary) != (was == BodyType.binary)) body = '';
    if (body != widget.request.body) {
      _body.text = body;
      _binaryPath.text = '';
    }
    widget.onChanged(
      widget.request.copyWith(bodyType: t, bodyAux: aux, body: body),
    );
  }

  bool get _textual {
    switch (widget.request.bodyType) {
      case BodyType.json:
      case BodyType.text:
      case BodyType.raw:
      case BodyType.graphql:
        return true;
      case BodyType.none:
      case BodyType.formUrlEncoded:
      case BodyType.multipart:
      case BodyType.binary:
        return false;
    }
  }

  Future<void> _chooseBinary() async {
    final picked = await context.read<FileService>().pickFile();
    if (picked == null) return;
    _binaryPath.text = picked.path;
    widget.onChanged(widget.request.copyWith(body: picked.path));
  }

  Future<void> _loadBody() async {
    final files = context.read<FileService>();
    final picked = await files.pickFile(
      extensions: widget.request.bodyType == BodyType.json
          ? <String>['json']
          : null,
    );
    if (picked == null) return;
    try {
      _body.text = await files.readText(picked.path, maxBytes: 5 * 1024 * 1024);
    } on FileTooLargeException {
      if (mounted) await showToast(context, context.t('body.fileTooLarge'));
    } on Exception catch (e) {
      if (mounted) {
        await showToast(context, context.t('ie.fileError', <String>['$e']));
      }
    }
  }

  Future<void> _saveBody() async {
    final r = widget.request;
    final name = r.bodyType == BodyType.json ? 'body.json' : 'body.txt';
    final path = await context.read<FileService>().saveText(name, _body.text);
    if (path != null && mounted) {
      await showToast(
        context,
        context.t('resp.savedTo', <String>[fileNameOf(path)]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final c = context.colors;
    final isHttp = r.kind == RequestKind.http;
    final types = isHttp ? BodyType.values : <BodyType>[BodyType.none];

    Widget content;
    switch (r.bodyType) {
      case BodyType.none:
        content = Center(
          child: Text(context.t('body.noneHint'), style: context.secondary),
        );
      case BodyType.json:
        content = Padding(
          padding: const EdgeInsets.all(10),
          child: SettingsCodeEditor(
            controller: _body,
            language: CodeLanguage.json,
            hintText: '{ }',
          ),
        );
      case BodyType.text:
        content = Padding(
          padding: const EdgeInsets.all(10),
          child: SettingsCodeEditor(
            controller: _body,
            language: CodeLanguage.text,
          ),
        );
      case BodyType.raw:
        content = Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: TextField(
                controller: _contentType,
                style: context.mono,
                decoration: InputDecoration(
                  labelText: context.t('body.contentType'),
                  hintText: 'text/plain',
                ),
                onChanged: (v) => widget.onChanged(r.copyWith(bodyAux: v)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SettingsCodeEditor(
                  controller: _body,
                  language: CodeLanguage.text,
                ),
              ),
            ),
          ],
        );
      case BodyType.graphql:
        content = Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.t('body.gqlQuery'), style: context.formLabel),
              const SizedBox(height: 4),
              Expanded(
                flex: 3,
                child: SettingsCodeEditor(
                  controller: _body,
                  language: CodeLanguage.text,
                ),
              ),
              const SizedBox(height: 10),
              Text(context.t('body.gqlVariables'), style: context.formLabel),
              const SizedBox(height: 4),
              Expanded(
                flex: 2,
                child: SettingsCodeEditor(
                  controller: _aux,
                  language: CodeLanguage.json,
                  hintText: '{ }',
                ),
              ),
            ],
          ),
        );
      case BodyType.binary:
        content = Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.t('body.binaryHint'), style: context.secondary),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _binaryPath,
                      style: context.mono,
                      decoration: InputDecoration(
                        labelText: context.t('body.filePath'),
                      ),
                      onChanged: (v) =>
                          widget.onChanged(r.copyWith(body: v.trim())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: Text(context.t('body.chooseFile')),
                    onPressed: _chooseBinary,
                  ),
                ],
              ),
            ],
          ),
        );
      case BodyType.formUrlEncoded:
        content = KeyValueEditor(
          items: r.formFields,
          onChanged: (v) => widget.onChanged(r.copyWith(formFields: v)),
        );
      case BodyType.multipart:
        content = Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.t('body.multipartHint'),
                  style: context.secondary,
                ),
              ),
            ),
            Expanded(
              child: KeyValueEditor(
                items: r.formFields,
                allowFile: true,
                onChanged: (v) => widget.onChanged(r.copyWith(formFields: v)),
              ),
            ),
          ],
        );
    }

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final t in types)
                      ChoiceChip(
                        label: Text(context.t(_labels[t]!)),
                        selected: r.bodyType == t,
                        selectedColor: c.accent.withAlpha(50),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _setType(t),
                      ),
                  ],
                ),
              ),
              if (_textual) ...<Widget>[
                IconButton(
                  tooltip: context.t('body.loadFile'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  onPressed: _loadBody,
                ),
                IconButton(
                  tooltip: context.t('body.saveFile'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.save_alt_outlined, size: 18),
                  onPressed: _saveBody,
                ),
              ],
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
