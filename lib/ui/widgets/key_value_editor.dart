import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/model/key_value.dart';
import '../../l10n/strings.dart';
import '../editor/code_editor_controller.dart';
import '../editor/highlighter.dart';

class _Row {
  _Row(KeyValue kv)
      : key = CodeEditorController(text: kv.key, language: CodeLanguage.text),
        value = CodeEditorController(text: kv.value, language: CodeLanguage.text),
        enabled = kv.enabled,
        isFile = kv.isFile;

  final CodeEditorController key;
  final CodeEditorController value;
  bool enabled;
  bool isFile;

  bool get blank => key.text.isEmpty && value.text.isEmpty;
  KeyValue toKv() => KeyValue(key: key.text, value: value.text, enabled: enabled, isFile: isFile);

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

/// Editable list of key/value rows with enable checkbox and an always-present
/// empty row at the end. Values highlight `{{variables}}`.
class KeyValueEditor extends StatefulWidget {
  const KeyValueEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.keyHint,
    this.valueHint,
    this.allowFile = false,
  });

  final List<KeyValue> items;
  final ValueChanged<List<KeyValue>> onChanged;
  final String? keyHint;
  final String? valueHint;

  /// Shows a toggle that turns the value into a file path (multipart).
  final bool allowFile;

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  late List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _build(widget.items);
  }

  List<_Row> _build(List<KeyValue> items) => <_Row>[
        ...items.map(_Row.new),
        _Row(const KeyValue()),
      ];

  bool _sameAs(List<KeyValue> items) {
    if (items.length != _rows.length - 1) return false;
    for (var i = 0; i < items.length; i++) {
      final r = _rows[i];
      final k = items[i];
      if (r.key.text != k.key || r.value.text != k.value || r.enabled != k.enabled || r.isFile != k.isFile) {
        return false;
      }
    }
    return true;
  }

  @override
  void didUpdateWidget(KeyValueEditor old) {
    super.didUpdateWidget(old);
    if (!_sameAs(widget.items)) {
      for (final r in _rows) {
        r.dispose();
      }
      _rows = _build(widget.items);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _emit() {
    if (!_rows.last.blank) {
      _rows.add(_Row(const KeyValue()));
    }
    final list = _rows.where((r) => !r.blank).map((r) => r.toKv()).toList();
    widget.onChanged(list);
    setState(() {});
  }

  void _remove(int i) {
    if (i >= _rows.length - 1) return;
    _rows.removeAt(i).dispose();
    _emit();
  }

  Widget _field(BuildContext context, CodeEditorController c, String? hint, bool enabled) {
    return TextField(
      controller: c,
      style: context.mono.copyWith(
        color: enabled ? context.colors.textPrimary : context.colors.textSecondary,
      ),
      decoration: InputDecoration(hintText: hint),
      onChanged: (_) => _emit(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, cons) {
      final narrow = cons.maxWidth < 460;
      return ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => SizedBox(height: narrow ? 12 : 6),
        itemBuilder: (ctx, i) {
          final r = _rows[i];
          final isLast = i == _rows.length - 1;
          final keyField = _field(ctx, r.key, widget.keyHint ?? ctx.t('kv.key'), r.enabled);
          final valueField = _field(
            ctx,
            r.value,
            r.isFile ? ctx.t('kv.filePath') : (widget.valueHint ?? ctx.t('kv.value')),
            r.enabled,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 32,
                child: isLast
                    ? null
                    : Checkbox(
                        value: r.enabled,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) {
                          r.enabled = v ?? true;
                          _emit();
                        },
                      ),
              ),
              Expanded(
                child: narrow
                    ? Column(children: <Widget>[keyField, const SizedBox(height: 6), valueField])
                    : Row(children: <Widget>[
                        Expanded(flex: 2, child: keyField),
                        const SizedBox(width: 6),
                        Expanded(flex: 3, child: valueField),
                      ]),
              ),
              if (widget.allowFile)
                IconButton(
                  tooltip: ctx.t('kv.toggleFile'),
                  icon: Icon(
                    r.isFile ? Icons.attach_file : Icons.text_fields,
                    size: 18,
                    color: r.isFile ? c.accent : c.textSecondary,
                  ),
                  onPressed: isLast
                      ? null
                      : () {
                          r.isFile = !r.isFile;
                          _emit();
                        },
                ),
              SizedBox(
                width: 36,
                child: isLast
                    ? null
                    : IconButton(
                        tooltip: ctx.t('common.delete'),
                        icon: Icon(Icons.close, size: 18, color: c.textSecondary),
                        onPressed: () => _remove(i),
                      ),
              ),
            ],
          );
        },
      );
    });
  }
}
