import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/design/tokens.dart';
import '../app/services.dart';
import '../core/design/typography.dart';
import '../core/platform/file_service.dart';
import '../core/platform/share_intent_service.dart';
import '../features/collections/application/collections_cubit.dart';
import '../features/environments/application/environments_cubit.dart';
import '../features/import_export/postman.dart' show kMaxImportBytes;
import '../features/requests/domain/request_models.dart';
import '../features/settings/application/settings_cubit.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/shortcuts/shortcut_catalog.dart';
import '../features/workspace/application/workspace_cubit.dart';
import '../l10n/strings.dart';
import 'cookies/cookies_page.dart';
import 'header/app_header.dart';
import 'widgets/brand.dart';
import 'env/environments_page.dart';
import 'import_export/import_export_page.dart';
import 'menu/menu_page.dart';
import 'palette/command_palette.dart';
import 'request/request_editor.dart';
import 'request/save_actions.dart';
import 'response/response_inspector.dart';
import 'runner/runner_page.dart';
import 'settings/settings_page.dart';
import 'shortcuts/key_mapping.dart';
import 'shortcuts/shortcuts_page.dart';
import 'sidebar/sidebar.dart';
import 'templates/templates_sheet.dart';
import 'workspaces/workspaces_page.dart';
import 'widgets/common.dart';
import 'widgets/env_selector.dart';
import 'widgets/soft.dart';
import 'workspace/workspace_view.dart';
import '../core/util/json_util.dart';
import 'widgets/pressable.dart';
import '../core/platform/platform_info.dart';
import 'insights/insights_page.dart';
import 'update/update_prompt.dart';

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
  bool _dragging = false;
  StreamSubscription<SharedContent>? _shareSub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WorkspaceCubit>();
    if (context.read<SettingsCubit>().state.restoreWorkspace) {
      _sidebarWidth = clampDouble(
        asDouble(ws.readLayout()['sidebar'], 300),
        220.0,
        480.0,
      );
    }
    // Content other Android apps share with PostBox opens the import preview.
    final share = context.read<ShareIntentService>();
    _shareSub = share.stream.listen(_onShared);
    share.init().then((c) {
      if (c != null && mounted) _onShared(c);
    });
    // Look for a newer release a moment after the window is up.
    if (context.read<AppServices>().enableUpdateCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) await checkForUpdatesOnStartup(context);
      });
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _onShared(SharedContent c) =>
      _push(ImportExportPage(initialImportText: c.text));

  /// A file dropped onto the window: show it in the import preview.
  Future<void> _onDropped(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final text = await context.read<FileService>().readText(
        paths.first,
        maxBytes: kMaxImportBytes,
      );
      if (mounted) _push(ImportExportPage(initialImportText: text));
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
      if (_mobilePage == 1 &&
          MediaQuery.of(context).size.width < kDesktopBreakpoint) {
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
        message: context.t('tabs.closeMsg', <String>[
          t.draft.displayName.isEmpty
              ? context.t('tabs.untitled')
              : t.draft.displayName,
        ]),
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
      PaletteItem(
        label: context.t('palette.newRequest'),
        icon: Icons.add,
        run: ws.newTab,
      ),
      PaletteItem(
        label: context.t('palette.send'),
        icon: Icons.send,
        run: _send,
      ),
      PaletteItem(
        label: context.t('palette.save'),
        icon: Icons.save_outlined,
        run: _save,
      ),
      PaletteItem(
        label: context.t('palette.settings'),
        icon: Icons.settings_outlined,
        run: () => _push(const SettingsPage()),
      ),
      PaletteItem(
        label: context.t('palette.environments'),
        icon: Icons.layers_outlined,
        run: () => _push(const EnvironmentsPage()),
      ),
      PaletteItem(
        label: context.t('palette.importExport'),
        icon: Icons.import_export,
        run: () => _push(const ImportExportPage()),
      ),
      PaletteItem(
        label: context.t('palette.fromTemplate'),
        icon: Icons.dashboard_customize_outlined,
        run: () => showTemplatePicker(context),
      ),
      PaletteItem(
        label: context.t('palette.cookies'),
        icon: Icons.cookie_outlined,
        run: () => _push(const CookiesPage()),
      ),
      PaletteItem(
        label: context.t('palette.workspaces'),
        icon: Icons.workspaces_outlined,
        run: () => _push(const WorkspacesPage()),
      ),
      PaletteItem(
        label: context.t('insights.title'),
        icon: Icons.insights_outlined,
        run: () => _push(const InsightsPage()),
      ),
      // The shortcut guide is for keyboards, so phones do not list it.
      if (isDesktopPlatform)
        PaletteItem(
          label: context.t('palette.shortcuts'),
          icon: Icons.keyboard_outlined,
          run: () => _push(const ShortcutsPage()),
        ),
      PaletteItem(
        label: context.t('palette.toggleTheme'),
        icon: Icons.brightness_6_outlined,
        run: () => settings.update(
          (s) => s.copyWith(
            themeMode: Theme.of(context).brightness == Brightness.dark
                ? AppThemeMode.light
                : AppThemeMode.dark,
          ),
        ),
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
            if (MediaQuery.of(context).size.width < kDesktopBreakpoint) {
              setState(() => _mobilePage = 1);
            }
          },
        ),
    ];
    showCommandPalette(context, items);
  }

  @override
  Widget build(BuildContext context) {
    final overrides = context.select((SettingsCubit c) => c.state.shortcuts);
    final ws = context.read<WorkspaceCubit>();
    final actions = <ShortcutAction, VoidCallback>{
      ShortcutAction.send: _send,
      ShortcutAction.save: _save,
      ShortcutAction.commandPalette: _palette,
      ShortcutAction.newTab: ws.newTab,
      ShortcutAction.closeTab: _closeActive,
      ShortcutAction.nextTab: () => ws.selectRelative(1),
      ShortcutAction.previousTab: () => ws.selectRelative(-1),
    };
    final bindings = <ShortcutActivator, VoidCallback>{};
    effectiveShortcuts(overrides).forEach((action, combo) {
      final activator = activatorFor(combo);
      if (activator != null) bindings[activator] = actions[action]!;
    });
    final dropEnabled = context.read<AppServices>().enableFileDrop;
    final content = _withDrop(context, bindings);
    if (!dropEnabled) return content;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _onDropped(d.files.map((f) => f.path).toList());
      },
      child: content,
    );
  }

  Widget _withDrop(
    BuildContext context,
    Map<ShortcutActivator, VoidCallback> bindings,
  ) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: CallbackShortcuts(
            bindings: bindings,
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, cons) {
                  return cons.maxWidth >= kDesktopBreakpoint
                      ? _desktop(context)
                      : _mobile(context);
                },
              ),
            ),
          ),
        ),
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: context.colors.accent.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRaised,
                    border: Border.all(color: context.colors.accent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.t('ie.dropHere'),
                    style: context.pageTitle,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- desktop ---------------------------------------------------------------

  Widget _desktop(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Column(
        children: <Widget>[
          AppHeader(
            onPalette: _palette,
            onImportExport: () => _push(const ImportExportPage()),
            onSettings: () => _push(const SettingsPage()),
            onWorkspaces: () => _push(const WorkspacesPage()),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(width: _sidebarWidth, child: const Sidebar()),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (_) {
                      final ws = context.read<WorkspaceCubit>();
                      ws.saveLayout(<String, dynamic>{
                        ...ws.readLayout(),
                        'sidebar': _sidebarWidth,
                      });
                    },
                    onHorizontalDragUpdate: (d) {
                      final rtl =
                          Directionality.of(context) == TextDirection.rtl;
                      setState(
                        () => _sidebarWidth = clampDouble(
                          _sidebarWidth + (rtl ? -d.delta.dx : d.delta.dx),
                          220.0,
                          480.0,
                        ),
                      );
                    },
                    child: Container(
                      width: 8,
                      alignment: Alignment.center,
                      child: Container(width: 1, color: c.border),
                    ),
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
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, s) {
        final tab = s.active;
        Widget body;
        switch (_mobilePage) {
          case 0:
            body = Sidebar(onOpened: () => setState(() => _mobilePage = 1));
          case 2:
            body = tab == null
                ? const SizedBox.shrink()
                : ResponseInspector(tab: tab);
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
        final name = tab == null || tab.draft.displayName.isEmpty
            ? context.t('tabs.untitled')
            : tab.draft.displayName;
        return Scaffold(
          appBar: _mobilePage == 3 ? null : _mobileAppBar(context, s, name),
          body: AccentGlow(
            child: SafeArea(top: _mobilePage == 3, bottom: false, child: body),
          ),
          bottomNavigationBar: FloatingNavBar(
            index: _mobilePage,
            onSelected: (i) => setState(() => _mobilePage = i),
            items: <NavItem>[
              NavItem(
                Icons.folder_outlined,
                Icons.folder,
                context.t('nav.library'),
              ),
              NavItem(
                Icons.edit_outlined,
                Icons.edit,
                context.t('nav.request'),
              ),
              NavItem(
                Icons.article_outlined,
                Icons.article,
                context.t('nav.response'),
              ),
              NavItem(Icons.menu, Icons.menu_open, context.t('nav.menu')),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _mobileAppBar(
    BuildContext context,
    WorkspaceState s,
    String name,
  ) {
    final c = context.colors;
    final library = _mobilePage == 0;
    final tab = s.active;
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsetsDirectional.only(start: 16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: BrandLogo(size: 30),
        ),
      ),
      shape: Border(bottom: BorderSide(color: c.border)),
      title: Pressable(
        borderRadius: BorderRadius.circular(10),
        onTap: library ? null : () => _tabSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      library ? context.t('nav.library') : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.pageTitle.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!library && tab != null)
                      Text(
                        tab.draft.kind == RequestKind.http
                            ? tab.draft.method
                            : (tab.draft.kind == RequestKind.sse
                                  ? 'SSE'
                                  : 'WebSocket'),
                        style: context.methodBadge.copyWith(
                          fontSize: 11,
                          color: c.methodColor(tab.draft.method),
                        ),
                      ),
                  ],
                ),
              ),
              if (!library && s.tabs.length > 1) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent.withAlpha(34),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${s.tabs.length}',
                    style: context.secondary.copyWith(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 20, color: c.textSecondary),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        const EnvSelector(),
        HeaderIconButton(
          tooltip: context.t('palette.title'),
          icon: Icons.search,
          onPressed: _palette,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _tabSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => BlocProvider<WorkspaceCubit>.value(
        value: context.read<WorkspaceCubit>(),
        child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
          builder: (ctx, s) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final t in s.tabs)
                      ListTile(
                        selected: t.id == s.activeId,
                        leading: SizedBox(
                          width: 48,
                          child: Text(
                            t.draft.kind == RequestKind.http
                                ? t.draft.method
                                : (t.draft.kind == RequestKind.sse
                                      ? 'SSE'
                                      : 'WS'),
                            style: ctx.methodBadge.copyWith(
                              color: ctx.colors.methodColor(t.draft.method),
                            ),
                          ),
                        ),
                        title: Text(
                          t.draft.displayName.isEmpty
                              ? ctx.t('tabs.untitled')
                              : t.draft.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: ctx.t('common.close'),
                          onPressed: () async {
                            if (t.dirty) {
                              final ok = await confirmDestructive(
                                ctx,
                                title: ctx.t('tabs.closeTitle'),
                                message: ctx.t('tabs.closeMsg', <String>[
                                  t.draft.displayName.isEmpty
                                      ? ctx.t('tabs.untitled')
                                      : t.draft.displayName,
                                ]),
                                confirmLabel: ctx.t('tabs.discard'),
                                force: true,
                              );
                              if (!ok) return;
                            }
                            if (ctx.mounted) {
                              await ctx.read<WorkspaceCubit>().closeTab(t.id);
                            }
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
          },
        ),
      ),
    );
  }
}
