import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/app_info.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../features/collections/application/collections_cubit.dart';
import '../features/environments/application/environments_cubit.dart';
import '../features/requests/domain/request_models.dart';
import '../features/settings/application/settings_cubit.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/workspace/application/workspace_cubit.dart';
import '../l10n/strings.dart';
import 'env/environments_page.dart';
import 'import_export/import_export_page.dart';
import 'menu/menu_page.dart';
import 'palette/command_palette.dart';
import 'request/request_editor.dart';
import 'request/save_actions.dart';
import 'response/response_inspector.dart';
import 'runner/runner_page.dart';
import 'settings/settings_page.dart';
import 'sidebar/sidebar.dart';
import 'widgets/common.dart';
import 'widgets/env_selector.dart';
import 'widgets/soft.dart';
import 'workspace/workspace_view.dart';
import '../core/util/json_util.dart';

/// Desktop layout from 900 logical pixels up, phone layout below.
const double kDesktopBreakpoint = 900;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  double _sidebarWidth = 300;
  int _mobilePage = 1; // 0 library, 1 request, 2 response, 3 menu

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  void _send() {
    final ws = context.read<WorkspaceCubit>();
    final t = ws.state.active;
    if (t == null) return;
    if (t.phase == SendPhase.sending) {
      ws.cancel(t.id);
    } else if (t.streaming) {
      ws.disconnect(t.id);
    } else {
      ws.send(t.id);
      if (_mobilePage == 1 && MediaQuery.of(context).size.width < kDesktopBreakpoint) {
        setState(() => _mobilePage = 2);
      }
    }
  }

  void _save() {
    final t = context.read<WorkspaceCubit>().state.active;
    if (t != null) saveTab(context, t);
  }

  Future<void> _closeActive() async {
    final ws = context.read<WorkspaceCubit>();
    final t = ws.state.active;
    if (t == null) return;
    if (t.dirty) {
      final ok = await confirmDestructive(
        context,
        title: context.t('tabs.closeTitle'),
        message: context.t('tabs.closeMsg', <String>[t.draft.displayName.isEmpty ? context.t('tabs.untitled') : t.draft.displayName]),
        confirmLabel: context.t('tabs.discard'),
        force: true,
      );
      if (!ok) return;
    }
    await ws.closeTab(t.id);
  }

  void _palette() {
    final collections = context.read<CollectionsCubit>().state;
    final envs = context.read<EnvironmentsCubit>().state;
    final settings = context.read<SettingsCubit>();
    final ws = context.read<WorkspaceCubit>();
    final items = <PaletteItem>[
      PaletteItem(label: context.t('palette.newRequest'), icon: Icons.add, run: ws.newTab),
      PaletteItem(label: context.t('palette.send'), icon: Icons.send, run: _send),
      PaletteItem(label: context.t('palette.save'), icon: Icons.save_outlined, run: _save),
      PaletteItem(label: context.t('palette.settings'), icon: Icons.settings_outlined, run: () => _push(const SettingsPage())),
      PaletteItem(label: context.t('palette.environments'), icon: Icons.layers_outlined, run: () => _push(const EnvironmentsPage())),
      PaletteItem(label: context.t('palette.importExport'), icon: Icons.import_export, run: () => _push(const ImportExportPage())),
      PaletteItem(
        label: context.t('palette.toggleTheme'),
        icon: Icons.brightness_6_outlined,
        run: () => settings.update((s) => s.copyWith(
              themeMode: Theme.of(context).brightness == Brightness.dark ? AppThemeMode.light : AppThemeMode.dark,
            )),
      ),
      PaletteItem(
        label: context.t('palette.noEnv'),
        icon: Icons.layers_clear_outlined,
        run: () => context.read<EnvironmentsCubit>().setActive(null),
      ),
      for (final e in envs.environments)
        PaletteItem(
          label: context.t('palette.useEnv', <String>[e.name]),
          icon: Icons.layers_outlined,
          run: () => context.read<EnvironmentsCubit>().setActive(e.id),
        ),
      for (final c in collections.collections)
        PaletteItem(
          label: context.t('palette.runCollection', <String>[c.name]),
          icon: Icons.play_circle_outline,
          run: () => _push(RunnerPage(collectionId: c.id)),
        ),
      for (final n in collections.nodes.where((n) => !n.isFolder))
        PaletteItem(
          label: n.name,
          hint: '${n.request?.method ?? ''} ${n.request?.url ?? ''}',
          icon: Icons.description_outlined,
          run: () {
            ws.openNode(n);
            if (MediaQuery.of(context).size.width < kDesktopBreakpoint) setState(() => _mobilePage = 1);
          },
        ),
    ];
    showCommandPalette(context, items);
  }

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _palette,
      const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => context.read<WorkspaceCubit>().newTab(),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): _closeActive,
    };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, cons) {
          return cons.maxWidth >= kDesktopBreakpoint ? _desktop(context) : _mobile(context);
        }),
      ),
    );
  }

  // --- desktop ---------------------------------------------------------------

  Widget _desktop(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Column(
        children: <Widget>[
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(7)),
                  child: Icon(Icons.inbox_rounded, size: 16, color: c.onAccent),
                ),
                const SizedBox(width: 10),
                Text(appName, style: context.pageTitle),
                const Spacer(),
                const EnvSelector(),
                const SizedBox(width: 6),
                IconButton(tooltip: '${context.t('palette.title')} (Ctrl+K)', icon: const Icon(Icons.search), onPressed: _palette),
                IconButton(tooltip: context.t('ie.title'), icon: const Icon(Icons.import_export), onPressed: () => _push(const ImportExportPage())),
                IconButton(tooltip: context.t('settings.title'), icon: const Icon(Icons.settings_outlined), onPressed: () => _push(const SettingsPage())),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(width: _sidebarWidth, child: const Sidebar()),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      final rtl = Directionality.of(context) == TextDirection.rtl;
                      setState(() => _sidebarWidth = clampDouble(_sidebarWidth + (rtl ? -d.delta.dx : d.delta.dx), 220.0, 480.0));
                    },
                    child: Container(width: 8, alignment: Alignment.center, child: Container(width: 1, color: c.border)),
                  ),
                ),
                const Expanded(child: WorkspaceView()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- phone --------------------------------------------------------------------

  Widget _mobile(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(builder: (context, s) {
      final tab = s.active;
      Widget body;
      switch (_mobilePage) {
        case 0:
          body = Sidebar(onOpened: () => setState(() => _mobilePage = 1));
        case 2:
          body = tab == null ? const SizedBox.shrink() : ResponseInspector(tab: tab);
        case 3:
          body = const MenuPage();
        default:
          body = tab == null
              ? EmptyState(icon: Icons.tab, title: context.t('tabs.none'))
              : RequestEditor(
                  key: ValueKey<String>(tab.id),
                  tab: tab,
                  compact: true,
                  onSent: () => setState(() => _mobilePage = 2),
                );
      }
      final name = tab == null || tab.draft.displayName.isEmpty ? context.t('tabs.untitled') : tab.draft.displayName;
      return Scaffold(
        appBar: _mobilePage == 3
            ? null
            : AppBar(
                titleSpacing: 16,
                title: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _tabSheet(context),
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Flexible(
                      child: Text(
                        _mobilePage == 0 ? context.t('nav.library') : name,
                        overflow: TextOverflow.ellipsis,
                        style: context.pageTitle.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (s.tabs.length > 1) ...<Widget>[
                      const SizedBox(width: 4),
                      Text('(${s.tabs.length})', style: context.secondary),
                    ],
                    const Icon(Icons.arrow_drop_down),
                  ]),
                ),
                actions: <Widget>[
                  const EnvSelector(),
                  IconButton(tooltip: context.t('palette.title'), icon: const Icon(Icons.search), onPressed: _palette),
                  const SizedBox(width: 4),
                ],
              ),
        body: AccentGlow(child: SafeArea(top: _mobilePage == 3, bottom: false, child: body)),
        bottomNavigationBar: FloatingNavBar(
          index: _mobilePage,
          onSelected: (i) => setState(() => _mobilePage = i),
          items: <NavItem>[
            NavItem(Icons.folder_outlined, Icons.folder, context.t('nav.library')),
            NavItem(Icons.edit_outlined, Icons.edit, context.t('nav.request')),
            NavItem(Icons.article_outlined, Icons.article, context.t('nav.response')),
            NavItem(Icons.menu, Icons.menu_open, context.t('nav.menu')),
          ],
        ),
      );
    });
  }

  Future<void> _tabSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => BlocProvider<WorkspaceCubit>.value(
        value: context.read<WorkspaceCubit>(),
        child: BlocBuilder<WorkspaceCubit, WorkspaceState>(builder: (ctx, s) {
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final t in s.tabs)
                    ListTile(
                      selected: t.id == s.activeId,
                      leading: SizedBox(
                        width: 48,
                        child: Text(
                          t.draft.kind == RequestKind.http ? t.draft.method : (t.draft.kind == RequestKind.sse ? 'SSE' : 'WS'),
                          style: ctx.methodBadge.copyWith(color: ctx.colors.methodColor(t.draft.method)),
                        ),
                      ),
                      title: Text(t.draft.displayName.isEmpty ? ctx.t('tabs.untitled') : t.draft.displayName, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: ctx.t('common.close'),
                        onPressed: () async {
                          if (t.dirty) {
                            final ok = await confirmDestructive(
                              ctx,
                              title: ctx.t('tabs.closeTitle'),
                              message: ctx.t('tabs.closeMsg', <String>[t.draft.displayName.isEmpty ? ctx.t('tabs.untitled') : t.draft.displayName]),
                              confirmLabel: ctx.t('tabs.discard'),
                              force: true,
                            );
                            if (!ok) return;
                          }
                          if (ctx.mounted) await ctx.read<WorkspaceCubit>().closeTab(t.id);
                        },
                      ),
                      onTap: () {
                        ctx.read<WorkspaceCubit>().select(t.id);
                        Navigator.pop(ctx);
                        setState(() => _mobilePage = 1);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(ctx.t('tabs.new')),
                    onTap: () {
                      ctx.read<WorkspaceCubit>().newTab();
                      Navigator.pop(ctx);
                      setState(() => _mobilePage = 1);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
