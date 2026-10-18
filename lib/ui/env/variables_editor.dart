import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/environments/domain/variables.dart';
import '../../l10n/strings.dart';

/// Editable variable list with enabled, secret flag and masked secret values.
class VariablesEditor extends StatefulWidget {
  const VariablesEditor({super.key, required this.variables, required this.onChanged});

  final List<Variable> variables;
  final ValueChanged<List<Variable>> onChanged;

  @override
  State<VariablesEditor> createState() => _VariablesEditorState();
}

class _VarRow {
  _VarRow(this.v)
      : key = TextEditingController(text: v.key),
        value = TextEditingController(text: v.value);
  Variable v;
  final TextEditingController key;
  final TextEditingController value;
  bool reveal = false;

  Variable current() => v.copyWith(key: key.text, value: value.text);
  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _VariablesEditorState extends State<VariablesEditor> {
  late List<_VarRow> _rows = widget.variables.map(_VarRow.new).toList();

  @override
  void didUpdateWidget(VariablesEditor old) {
    super.didUpdateWidget(old);
    final same = widget.variables.length == _rows.length &&
        List<bool>.generate(_rows.length, (i) => _rows[i].v.id == widget.variables[i].id).every((e) => e);
    if (!same) {
      for (final r in _rows) {
        r.dispose();
      }
      _rows = widget.variables.map(_VarRow.new).toList();
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
    for (final r in _rows) {
      r.v = r.current();
    }
    widget.onChanged(_rows.map((r) => r.v).toList());
    setState(() {});
  }

  void _add() {
    _rows.add(_VarRow(Variable.blank()));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: <Widget>[
        Expanded(
          child: _rows.isEmpty
              ? Center(child: Text(context.t('env.noVars'), style: context.secondary))
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final r = _rows[i];
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Checkbox(
                          value: r.v.enabled,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) {
                            r.v = r.v.copyWith(enabled: v ?? true);
                            _emit();
                          },
                        ),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: r.key,
                            style: ctx.mono,
                            decoration: InputDecoration(hintText: ctx.t('env.name')),
                            onChanged: (_) => _emit(),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: TextField(
                            controller: r.value,
                            style: ctx.mono,
                            obscureText: r.v.secret && !r.reveal,
                            enableSuggestions: !r.v.secret,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: ctx.t('env.value'),
                              suffixIcon: r.v.secret
                                  ? IconButton(
                                      tooltip: ctx.t('auth.reveal'),
                                      icon: Icon(r.reveal ? Icons.visibility_off : Icons.visibility, size: 18, color: c.textSecondary),
                                      onPressed: () => setState(() => r.reveal = !r.reveal),
                                    )
                                  : null,
                            ),
                            onChanged: (_) => _emit(),
                          ),
                        ),
                        FilterChip(
                          label: Text(ctx.t('env.secret')),
                          selected: r.v.secret,
                          avatar: Icon(Icons.lock_outline, size: 14, color: r.v.secret ? c.accent : c.textSecondary),
                          visualDensity: VisualDensity.compact,
                          onSelected: (s) {
                            r.v = r.v.copyWith(secret: s);
                            _emit();
                          },
                        ),
                        IconButton(
                          tooltip: ctx.t('common.delete'),
                          icon: Icon(Icons.close, size: 18, color: c.textSecondary),
                          onPressed: () {
                            _rows.removeAt(i).dispose();
                            _emit();
                          },
                        ),
                      ],
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.t('env.addVar')),
            ),
          ),
        ),
      ],
    );
  }
}
