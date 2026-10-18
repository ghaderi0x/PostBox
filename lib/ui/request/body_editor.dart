import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/requests/domain/request_models.dart';
import '../../l10n/strings.dart';
import '../editor/code_editor_controller.dart';
import '../editor/highlighter.dart';
import '../editor/settings_code_editor.dart';
import '../widgets/key_value_editor.dart';

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

  @override
  void initState() {
    super.initState();
    _body = CodeEditorController(text: widget.request.body);
    _aux = CodeEditorController(text: widget.request.bodyAux);
    _contentType = TextEditingController(text: widget.request.bodyAux);
    _body.addListener(_onBody);
    _aux.addListener(_onAux);
  }

  @override
  void dispose() {
    _body.dispose();
    _aux.dispose();
    _contentType.dispose();
    super.dispose();
  }

  void _onBody() {
    if (_body.text != widget.request.body) {
      widget.onChanged(widget.request.copyWith(body: _body.text));
    }
  }

  void _onAux() {
    if (widget.request.bodyType == BodyType.graphql && _aux.text != widget.request.bodyAux) {
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
  };

  void _setType(BodyType t) {
    // The raw type reuses bodyAux for Content-Type, GraphQL for variables.
    final aux = t == BodyType.raw
        ? _contentType.text
        : (t == BodyType.graphql ? _aux.text : widget.request.bodyAux);
    widget.onChanged(widget.request.copyWith(bodyType: t, bodyAux: aux));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final c = context.colors;
    final isHttp = r.kind == RequestKind.http;
    final types = isHttp
        ? BodyType.values
        : <BodyType>[BodyType.none];

    Widget content;
    switch (r.bodyType) {
      case BodyType.none:
        content = Center(child: Text(context.t('body.noneHint'), style: context.secondary));
      case BodyType.json:
        content = Padding(
          padding: const EdgeInsets.all(10),
          child: SettingsCodeEditor(controller: _body, language: CodeLanguage.json, hintText: '{ }'),
        );
      case BodyType.text:
        content = Padding(
          padding: const EdgeInsets.all(10),
          child: SettingsCodeEditor(controller: _body, language: CodeLanguage.text),
        );
      case BodyType.raw:
        content = Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: TextField(
                controller: _contentType,
                style: context.mono,
                decoration: InputDecoration(labelText: context.t('body.contentType'), hintText: 'text/plain'),
                onChanged: (v) => widget.onChanged(r.copyWith(bodyAux: v)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SettingsCodeEditor(controller: _body, language: CodeLanguage.text),
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
              Expanded(flex: 3, child: SettingsCodeEditor(controller: _body, language: CodeLanguage.text)),
              const SizedBox(height: 10),
              Text(context.t('body.gqlVariables'), style: context.formLabel),
              const SizedBox(height: 4),
              Expanded(flex: 2, child: SettingsCodeEditor(controller: _aux, language: CodeLanguage.json, hintText: '{ }')),
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
                child: Text(context.t('body.multipartHint'), style: context.secondary),
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
        Expanded(child: content),
      ],
    );
  }
}
