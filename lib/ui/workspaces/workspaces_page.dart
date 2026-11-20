import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/workspaces/workspace_registry.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

/// Workspaces: separate sets of collections, environments, history, cookies
/// and templates. Settings and secrets are shared by all workspaces.
class WorkspacesPage extends StatefulWidget {
  const WorkspacesPage({super.key});

  @override
  State<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends State<WorkspacesPage> {
  WorkspaceManager get _m => context.read<WorkspaceManager>();

  Future<void> _switch(WorkspaceInfo w) async {
    if (w.id == _m.registry.activeId) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    // The root rebuilds the whole app with the other workspace's database.
    await _m.switchTo(w.id);
  }

  Future<void> _create() async {
    final name = await promptText(
      context,
      title: context.t('ws.new'),
      label: context.t('common.name'),
    );
    if (name == null) return;
    try {
      final w = await _m.registry.create(name);
      if (!mounted) return;
      setState(() {});
      await showToast(context, context.t('ws.created', <String>[w.name]));
    } on StateError {
      if (mounted) {
        await showToast(
          context,
          context.t('ws.limit', <String>['${WorkspaceRegistry.maxWorkspaces}']),
        );
      }
    }
  }

  Future<void> _rename(WorkspaceInfo w) async {
    final name = await promptText(
      context,
      title: context.t('common.rename'),
      initial: w.name,
      label: context.t('common.name'),
    );
    if (name == null) return;
    await _m.registry.rename(w.id, name);
    if (mounted) setState(() {});
  }

  Future<void> _delete(WorkspaceInfo w) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('ws.delete'),
      message: context.t('ws.deleteConfirm', <String>[w.name]),
      confirmLabel: context.t('common.delete'),
      force: true,
    );
    if (!ok) return;
    await _m.removeWorkspace(w.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reg = _m.registry;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('ws.title')),
        actions: <Widget>[
          IconButton(
            tooltip: context.t('ws.new'),
            icon: const Icon(Icons.add),
            onPressed: _create,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          InfoBanner(context.t('ws.info')),
          const SizedBox(height: 10),
          for (final w in reg.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                w.id == reg.activeId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: w.id == reg.activeId ? c.accent : c.textSecondary,
              ),
              title: Text(
                w.id == kDefaultWorkspaceId && w.name == 'Default'
                    ? context.t('ws.default')
                    : w.name,
                style: context.body,
              ),
              subtitle: w.id == reg.activeId
                  ? Text(context.t('ws.active'), style: context.secondary)
                  : null,
              onTap: () => _switch(w),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'rename') _rename(w);
                  if (v == 'delete') _delete(w);
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text(context.t('common.rename')),
                  ),
                  if (w.id != kDefaultWorkspaceId && w.id != reg.activeId)
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(context.t('common.delete')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
