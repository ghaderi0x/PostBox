import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/shortcuts/shortcut_catalog.dart';
import '../../l10n/strings.dart';
import 'key_mapping.dart';

/// Lists every shortcut and lets the user record a different key combination.
/// Changes are saved in the settings and take effect immediately.
class ShortcutsPage extends StatelessWidget {
  const ShortcutsPage({super.key});

  Future<void> _record(BuildContext context, ShortcutAction action) async {
    final cubit = context.read<SettingsCubit>();
    final current = effectiveShortcuts(cubit.state.shortcuts);
    final combo = await showDialog<KeyCombo>(
      context: context,
      builder: (_) => _RecordDialog(action: action, current: current),
    );
    if (combo == null) return;
    await cubit.update(
      (s) => s.copyWith(
        shortcuts: <String, String>{
          ...s.shortcuts,
          action.name: combo.serialize(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('shortcuts.title'))),
      body: BlocBuilder<SettingsCubit, dynamic>(
        builder: (context, _) {
          final settings = context.read<SettingsCubit>().state;
          final map = effectiveShortcuts(settings.shortcuts);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(context.t('shortcuts.hint'), style: context.secondary),
              const SizedBox(height: 12),
              for (final a in ShortcutAction.values)
                ListTile(
                  title: Text(context.t('shortcuts.action.${a.name}')),
                  subtitle: Text(
                    map[a]!.display(),
                    style: context.mono.copyWith(color: c.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (settings.shortcuts.containsKey(a.name))
                        IconButton(
                          tooltip: context.t('shortcuts.reset'),
                          icon: const Icon(Icons.restart_alt),
                          onPressed: () => context.read<SettingsCubit>().update(
                            (s) => s.copyWith(
                              shortcuts: <String, String>{...s.shortcuts}
                                ..remove(a.name),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => _record(context, a),
                        child: Text(context.t('shortcuts.change')),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: Text(context.t('shortcuts.resetAll')),
                  onPressed: settings.shortcuts.isEmpty
                      ? null
                      : () => context.read<SettingsCubit>().update(
                          (s) =>
                              s.copyWith(shortcuts: const <String, String>{}),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.action, required this.current});
  final ShortcutAction action;
  final Map<ShortcutAction, KeyCombo> current;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  String? _error;
  KeyCombo? _preview;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final combo = comboFromEvent(event);
    if (combo == null) return KeyEventResult.handled;
    if (!combo.isValid) {
      setState(() {
        _preview = combo;
        _error = context.t('shortcuts.invalid');
      });
      return KeyEventResult.handled;
    }
    final clash = findShortcutConflict(
      widget.current,
      combo,
      except: widget.action,
    );
    if (clash != null) {
      setState(() {
        _preview = combo;
        _error = context.t('shortcuts.conflict', <String>[
          context.t('shortcuts.action.${clash.name}'),
        ]);
      });
      return KeyEventResult.handled;
    }
    Navigator.of(context).pop(combo);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text(context.t('shortcuts.action.${widget.action.name}')),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _preview?.display() ?? context.t('shortcuts.press'),
              style: context.pageTitle.copyWith(fontSize: 20),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: context.secondary.copyWith(color: c.danger)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('common.cancel')),
        ),
      ],
    );
  }
}
