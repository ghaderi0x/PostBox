import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/collections/domain/collection_models.dart';
import '../../features/environments/domain/variables.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../env/variables_editor.dart';
import '../import_export/import_export_page.dart';
import '../runner/runner_page.dart';
import '../widgets/common.dart';
import 'save_dialog.dart';

class CollectionsPanel extends StatelessWidget {
  const CollectionsPanel({super.key, this.onOpened});

  /// Called after a request was opened (phones switch to the request page).
  final VoidCallback? onOpened;

  Future<void> _open(BuildContext context, NodeRecord n) async {
    await context.read<WorkspaceCubit>().openNode(n);
    onOpened?.call();
  }

  Future<void> _newCollection(BuildContext context) async {
    final name = await promptText(context, title: context.t('collections.new'), label: context.t('common.name'));
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await context.read<CollectionsCubit>().createCollection(name);
    }
  }

  Future<void> _newFolder(BuildContext context, String collectionId, String? parentId) async {
    final name = await promptText(context, title: context.t('collections.newFolder'), label: context.t('common.name'));
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await context.read<CollectionsCubit>().createFolder(collectionId, parentId, name);
    }
  }

  Future<void> _newRequest(BuildContext context, String collectionId, String? parentId) async {
    final ws = context.read<WorkspaceCubit>();
    ws.newTab();
    final tab = ws.state.active!;
    // Saved immediately so it shows up in the tree.
    await ws.save(tab.id, collectionId: collectionId, parentId: parentId);
    onOpened?.call();
  }

  Future<void> _rename(BuildContext context, String id, String current) async {
    final name = await promptText(context, title: context.t('common.rename'), initial: current, label: context.t('common.name'));
    if (name != null && context.mounted) context.read<CollectionsCubit>().rename(id, name);
  }

  Future<void> _renameCollection(BuildContext context, CollectionRecord c) async {
    final name = await promptText(context, title: context.t('common.rename'), initial: c.name, label: context.t('common.name'));
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await context.read<CollectionsCubit>().updateCollection(c.copyWith(name: name.trim()));
    }
  }

  Future<void> _deleteNode(BuildContext context, NodeRecord n) async {
    final ok = await confirmDestructive(
      context,
      title: context.t(n.isFolder ? 'collections.deleteFolderTitle' : 'collections.deleteRequestTitle'),
      message: context.t('collections.deleteMsg', <String>[n.name]),
    );
    if (!ok || !context.mounted) return;
    // Close open tabs of removed requests.
    final ws = context.read<WorkspaceCubit>();
    final col = context.read<CollectionsCubit>();
    final removedIds = <String>{n.id};
    void collect(String id) {
      for (final x in col.state.nodes.where((x) => x.parentId == id)) {
        removedIds.add(x.id);
        collect(x.id);
      }
    }

    collect(n.id);
    for (final id in removedIds) {
      if (ws.state.tab(id) != null) await ws.closeTab(id);
    }
    await col.deleteNode(n.id);
  }

  Future<void> _deleteCollection(BuildContext context, CollectionRecord c) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('collections.deleteTitle'),
      message: context.t('collections.deleteMsg', <String>[c.name]),
    );
    if (!ok || !context.mounted) return;
    final ws = context.read<WorkspaceCubit>();
    final col = context.read<CollectionsCubit>();
    for (final n in col.state.nodes.where((n) => n.collectionId == c.id)) {
      if (ws.state.tab(n.id) != null) await ws.closeTab(n.id);
    }
    await col.deleteCollection(c.id);
  }

  Future<void> _move(BuildContext context, NodeRecord n) async {
    final target = await showSaveRequestDialog(
      context,
      initialName: n.name,
      preferredCollectionId: n.collectionId,
      titleKey: 'collections.moveTitle',
      confirmKey: 'collections.move',
      askName: false,
    );
    if (target == null || !context.mounted) return;
    try {
      context.read<CollectionsCubit>().moveTo(n.id, collectionId: target.collectionId, parentId: target.parentId);
    } on ArgumentError {
      await showToast(context, context.t('collections.moveInvalid'));
    }
  }

  List<Widget> _tree(BuildContext context, CollectionsState s, String collectionId, String? parent, int depth) {
    final out = <Widget>[];
    for (final n in s.childrenOf(collectionId, parent)) {
      if (n.isFolder) {
        final open = s.expanded.contains(n.id);
        out.add(_Row(
          depth: depth,
          leading: Icon(open ? Icons.folder_open : Icons.folder_outlined, size: 18, color: context.colors.textSecondary),
          title: n.name,
          chevron: open,
          onTap: () => context.read<CollectionsCubit>().toggleExpanded(n.id),
          menu: <_MenuItem>[
            _MenuItem('collections.newRequest', () => _newRequest(context, collectionId, n.id)),
            _MenuItem('collections.newFolder', () => _newFolder(context, collectionId, n.id)),
            _MenuItem('common.rename', () => _rename(context, n.id, n.name)),
            _MenuItem('common.duplicate', () => context.read<CollectionsCubit>().duplicate(n.id, suffix: ' ${context.t('common.copySuffix')}')),
            _MenuItem('collections.moveUp', () => context.read<CollectionsCubit>().moveBy(n.id, -1)),
            _MenuItem('collections.moveDown', () => context.read<CollectionsCubit>().moveBy(n.id, 1)),
            _MenuItem('collections.move', () => _move(context, n)),
            _MenuItem('common.delete', () => _deleteNode(context, n)),
          ],
        ));
        if (open) out.addAll(_tree(context, s, collectionId, n.id, depth + 1));
      } else {
        out.add(_requestRow(context, s, n, depth));
      }
    }
    return out;
  }

  Widget _requestRow(BuildContext context, CollectionsState s, NodeRecord n, int depth, {String? subtitle}) {
    final c = context.colors;
    final active = context.watch<WorkspaceCubit>().state.activeId == n.id;
    return _Row(
      depth: depth,
      selected: active,
      leading: MethodBadge(n.request?.method ?? 'GET', width: 46),
      title: n.name,
      subtitle: subtitle,
      trailing: n.favorite ? Icon(Icons.star, size: 14, color: c.warning) : null,
      onTap: () => _open(context, n),
      menu: <_MenuItem>[
        _MenuItem('collections.open', () => _open(context, n)),
        _MenuItem(n.favorite ? 'collections.unfavorite' : 'collections.favorite', () => context.read<CollectionsCubit>().toggleFavorite(n.id)),
        _MenuItem('common.rename', () => _rename(context, n.id, n.name)),
        _MenuItem('common.duplicate', () => context.read<CollectionsCubit>().duplicate(n.id, suffix: ' ${context.t('common.copySuffix')}')),
        _MenuItem('collections.moveUp', () => context.read<CollectionsCubit>().moveBy(n.id, -1)),
        _MenuItem('collections.moveDown', () => context.read<CollectionsCubit>().moveBy(n.id, 1)),
        _MenuItem('collections.move', () => _move(context, n)),
        _MenuItem('common.delete', () => _deleteNode(context, n)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollectionsCubit, CollectionsState>(builder: (context, s) {
      final c = context.colors;
      final query = s.query.trim();
      final results = query.isEmpty ? const <NodeRecord>[] : s.search(query);

      final children = <Widget>[];
      if (query.isNotEmpty) {
        if (results.isEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: Text(context.t('collections.noResults'), style: context.secondary)),
          ));
        }
        for (final n in results) {
          children.add(_requestRow(context, s, n, 0, subtitle: s.collection(n.collectionId)?.name));
        }
      } else {
        final favs = s.favorites;
        final recents = s.recents();
        if (favs.isNotEmpty) {
          children.add(SectionTitle(context.t('collections.favorites')));
          for (final n in favs) {
            children.add(_requestRow(context, s, n, 0));
          }
        }
        if (recents.isNotEmpty) {
          children.add(SectionTitle(context.t('collections.recents')));
          for (final n in recents) {
            children.add(_requestRow(context, s, n, 0));
          }
        }
        children.add(SectionTitle(
          context.t('collections.title'),
          trailing: IconButton(
            tooltip: context.t('collections.new'),
            icon: Icon(Icons.add, size: 18, color: c.textSecondary),
            onPressed: () => _newCollection(context),
          ),
        ));
        if (s.collections.isEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.all(12),
            child: EmptyState(
              icon: Icons.folder_copy_outlined,
              title: context.t('collections.emptyTitle'),
              message: context.t('collections.emptyMsg'),
              action: FilledButton(onPressed: () => _newCollection(context), child: Text(context.t('collections.new'))),
            ),
          ));
        }
        for (final col in s.collections) {
          final open = s.expanded.contains(col.id);
          children.add(_Row(
            depth: 0,
            leading: Icon(open ? Icons.folder_open : Icons.folder, size: 18, color: c.accent),
            title: col.name,
            chevron: open,
            bold: true,
            onTap: () => context.read<CollectionsCubit>().toggleExpanded(col.id),
            menu: <_MenuItem>[
              _MenuItem('collections.newRequest', () => _newRequest(context, col.id, null)),
              _MenuItem('collections.newFolder', () => _newFolder(context, col.id, null)),
              _MenuItem('common.rename', () => _renameCollection(context, col)),
              _MenuItem('collections.variables', () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CollectionVariablesPage(collectionId: col.id),
                  ))),
              _MenuItem('runner.run', () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => RunnerPage(collectionId: col.id),
                  ))),
              _MenuItem('ie.exportCollection', () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ImportExportPage(initialCollectionId: col.id),
                  ))),
              _MenuItem('common.delete', () => _deleteCollection(context, col)),
            ],
          ));
          if (open) children.addAll(_tree(context, s, col.id, null, 1));
        }
      }

      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: context.read<CollectionsCubit>().setQuery,
                decoration: InputDecoration(
                  hintText: context.t('collections.search'),
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
            ),
          ),
          Expanded(child: ListView(children: children)),
        ],
      );
    });
  }
}

class _MenuItem {
  const _MenuItem(this.labelKey, this.run);
  final String labelKey;
  final VoidCallback run;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.depth,
    required this.leading,
    required this.title,
    required this.onTap,
    required this.menu,
    this.subtitle,
    this.trailing,
    this.chevron,
    this.selected = false,
    this.bold = false,
  });

  final int depth;
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool? chevron;
  final bool selected;
  final bool bold;
  final VoidCallback onTap;
  final List<_MenuItem> menu;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? c.accent.withAlpha(30) : null,
        padding: EdgeInsetsDirectional.fromSTEB(8 + depth * 14.0, 0, 0, 0),
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: <Widget>[
            if (chevron != null)
              Icon(chevron! ? Icons.expand_more : Icons.chevron_right, size: 16, color: c.textSecondary)
            else
              const SizedBox(width: 16),
            const SizedBox(width: 2),
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title.isEmpty ? '—' : title,
                    overflow: TextOverflow.ellipsis,
                    style: context.body.copyWith(fontWeight: bold ? FontWeight.w600 : null),
                  ),
                  if (subtitle != null) Text(subtitle!, overflow: TextOverflow.ellipsis, style: context.secondary),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            PopupMenuButton<int>(
              tooltip: context.t('common.more'),
              icon: Icon(Icons.more_horiz, size: 18, color: c.textSecondary),
              padding: EdgeInsets.zero,
              onSelected: (i) => menu[i].run(),
              itemBuilder: (ctx) => <PopupMenuEntry<int>>[
                for (var i = 0; i < menu.length; i++)
                  PopupMenuItem<int>(value: i, child: Text(ctx.t(menu[i].labelKey))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits the variables of one collection.
class CollectionVariablesPage extends StatefulWidget {
  const CollectionVariablesPage({super.key, required this.collectionId});
  final String collectionId;

  @override
  State<CollectionVariablesPage> createState() => _CollectionVariablesPageState();
}

class _CollectionVariablesPageState extends State<CollectionVariablesPage> {
  List<Variable>? _working;

  @override
  Widget build(BuildContext context) {
    final col = context.read<CollectionsCubit>().state.collection(widget.collectionId);
    if (col == null) return Scaffold(appBar: AppBar());
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('collections.variablesOf', <String>[col.name])),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _working == null
                ? null
                : () async {
                    final cubit = context.read<CollectionsCubit>();
                    await cubit.updateCollection(
                      col.copyWith(variables: _working!.where((v) => v.key.trim().isNotEmpty).toList()),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(context.t('common.save')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: VariablesEditor(
        variables: _working ?? col.variables,
        onChanged: (v) => setState(() => _working = v),
      ),
    );
  }
}
