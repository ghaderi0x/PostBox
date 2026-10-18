import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/ids.dart';
import '../../features/environments/application/environments_cubit.dart';
import '../../features/environments/domain/variables.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';
import 'variables_editor.dart';

const String _globalsId = '__globals__';

/// Manage global variables and named environments.
class EnvironmentsPage extends StatefulWidget {
  const EnvironmentsPage({super.key});

  @override
  State<EnvironmentsPage> createState() => _EnvironmentsPageState();
}

class _EnvironmentsPageState extends State<EnvironmentsPage> {
  String _selected = _globalsId;
  List<Variable>? _working;
  bool _dirty = false;

  List<Variable> _sourceVars(EnvironmentsState s) {
    if (_selected == _globalsId) return s.globals;
    final e = s.environments.where((e) => e.id == _selected).firstOrNull;
    return e?.variables ?? const <Variable>[];
  }

  Future<bool> _discardOk() async {
    if (!_dirty) return true;
    return confirmDestructive(
      context,
      title: context.t('env.unsavedTitle'),
      message: context.t('env.unsavedMsg'),
      confirmLabel: context.t('env.discard'),
      force: true,
    );
  }

  Future<void> _select(String id) async {
    if (id == _selected || !await _discardOk()) return;
    setState(() {
      _selected = id;
      _working = null;
      _dirty = false;
    });
  }

  Future<void> _save(EnvironmentsState s) async {
    final cubit = context.read<EnvironmentsCubit>();
    final vars = _working ?? _sourceVars(s);
    final cleaned = vars.where((v) => v.key.trim().isNotEmpty).toList();
    if (_selected == _globalsId) {
      await cubit.saveGlobals(cleaned);
    } else {
      final env = s.environments.firstWhere((e) => e.id == _selected);
      await cubit.save(env.copyWith(variables: cleaned));
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    await showToast(context, context.t('common.saved'));
  }

  Future<void> _create() async {
    if (!await _discardOk() || !mounted) return;
    final name = await promptText(context, title: context.t('env.new'), label: context.t('common.name'));
    if (name == null || name.trim().isEmpty || !mounted) return;
    final env = await context.read<EnvironmentsCubit>().create(name);
    setState(() {
      _selected = env.id;
      _working = null;
      _dirty = false;
    });
  }

  Future<void> _rename(Environment e) async {
    final name = await promptText(context, title: context.t('common.rename'), initial: e.name, label: context.t('common.name'));
    if (name == null || name.trim().isEmpty || !mounted) return;
    await context.read<EnvironmentsCubit>().save(e.copyWith(name: name.trim()));
  }

  Future<void> _duplicate(Environment e) async {
    final cubit = context.read<EnvironmentsCubit>();
    final copy = Environment(
      id: newId(),
      name: '${e.name} ${context.t('common.copySuffix')}',
      variables: e.variables.map((v) => Variable(id: newId(), key: v.key, value: v.value, secret: v.secret, enabled: v.enabled)).toList(),
    );
    await cubit.save(copy);
    if (mounted) setState(() => _selected = copy.id);
  }

  Future<void> _delete(Environment e) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('env.deleteTitle'),
      message: context.t('env.deleteMsg', <String>[e.name]),
    );
    if (!ok || !mounted) return;
    await context.read<EnvironmentsCubit>().delete(e.id);
    if (mounted) {
      setState(() {
        _selected = _globalsId;
        _working = null;
        _dirty = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<EnvironmentsCubit, EnvironmentsState>(builder: (context, s) {
      final env = _selected == _globalsId ? null : s.environments.where((e) => e.id == _selected).firstOrNull;
      if (_selected != _globalsId && env == null) {
        // The selected environment was removed elsewhere.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selected = _globalsId);
        });
      }
      final vars = _working ?? _sourceVars(s);
      return Scaffold(
        appBar: AppBar(
          title: Text(context.t('env.title')),
          actions: <Widget>[
            TextButton.icon(
              onPressed: _dirty ? () => _save(s) : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(context.t('common.save')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: <Widget>[
            if (!s.secretsPersistent)
              Padding(
                padding: const EdgeInsets.all(10),
                child: InfoBanner(context.t('env.secretsMemoryOnly'), warning: true),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(context.t('env.globals')),
                    selected: _selected == _globalsId,
                    onSelected: (_) => _select(_globalsId),
                  ),
                  for (final e in s.environments)
                    ChoiceChip(
                      avatar: s.activeId == e.id ? Icon(Icons.check_circle, size: 16, color: c.success) : null,
                      label: Text(e.name),
                      selected: _selected == e.id,
                      onSelected: (_) => _select(e.id),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(context.t('env.new')),
                    onPressed: _create,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      env == null ? context.t('env.globalsHint') : context.t('env.precedence'),
                      style: context.secondary,
                    ),
                  ),
                  if (env != null) ...<Widget>[
                    TextButton(
                      onPressed: s.activeId == env.id
                          ? null
                          : () => context.read<EnvironmentsCubit>().setActive(env.id),
                      child: Text(context.t(s.activeId == env.id ? 'env.active' : 'env.makeActive')),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            _rename(env);
                          case 'dup':
                            _duplicate(env);
                          case 'del':
                            _delete(env);
                        }
                      },
                      itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(value: 'rename', child: Text(ctx.t('common.rename'))),
                        PopupMenuItem<String>(value: 'dup', child: Text(ctx.t('common.duplicate'))),
                        PopupMenuItem<String>(value: 'del', child: Text(ctx.t('common.delete'))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: VariablesEditor(
                key: ValueKey<String>(_selected),
                variables: vars,
                onChanged: (v) => setState(() {
                  _working = v;
                  _dirty = true;
                }),
              ),
            ),
          ],
        ),
      );
    });
  }
}
