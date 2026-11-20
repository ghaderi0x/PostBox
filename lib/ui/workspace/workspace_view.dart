import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../request/request_editor.dart';
import '../response/response_inspector.dart';
import '../widgets/common.dart';
import '../../core/util/json_util.dart';
import '../widgets/pressable.dart';

/// Desktop workspace: tab strip plus resizable request/response split.
class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key});

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  double _fraction = 0.5;
  bool _horizontal = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsCubit>().state;
    if (settings.restoreWorkspace) {
      final l = context.read<WorkspaceCubit>().readLayout();
      _fraction = clampDouble(asDouble(l['fraction'], 0.5), 0.2, 0.8);
      _horizontal = asBool(l['horizontal'], false);
    }
  }

  void _saveLayout() {
    final ws = context.read<WorkspaceCubit>();
    final old = ws.readLayout();
    ws.saveLayout(<String, dynamic>{
      ...old,
      'fraction': _fraction,
      'horizontal': _horizontal,
    });
  }

  Future<void> _close(BuildContext context, RequestTab t) async {
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
    if (context.mounted) await context.read<WorkspaceCubit>().closeTab(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, s) {
        final tab = s.active;
        return Column(
          children: <Widget>[
            Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      itemCount: s.tabs.length,
                      onReorder: (o, n) =>
                          context.read<WorkspaceCubit>().reorderTabs(o, n),
                      proxyDecorator: (child, index, animation) => Material(
                        color: Colors.transparent,
                        elevation: 2,
                        child: child,
                      ),
                      footer: IconButton(
                        tooltip: context.t('tabs.new'),
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () =>
                            context.read<WorkspaceCubit>().newTab(),
                      ),
                      itemBuilder: (context, i) {
                        final t = s.tabs[i];
                        return ReorderableDragStartListener(
                          key: ValueKey<String>('tab-${t.id}'),
                          index: i,
                          child: _TabChip(
                            tab: t,
                            active: t.id == s.activeId,
                            onTap: () =>
                                context.read<WorkspaceCubit>().select(t.id),
                            onClose: () => _close(context, t),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('tabs.layout'),
                    icon: Icon(
                      _horizontal
                          ? Icons.view_agenda_outlined
                          : Icons.view_column_outlined,
                      size: 18,
                      color: c.textSecondary,
                    ),
                    onPressed: () {
                      setState(() => _horizontal = !_horizontal);
                      _saveLayout();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: tab == null
                  ? EmptyState(icon: Icons.tab, title: context.t('tabs.none'))
                  : LayoutBuilder(
                      builder: (context, cons) {
                        final request = RequestEditor(
                          key: ValueKey<String>(tab.id),
                          tab: tab,
                        );
                        final response = ResponseInspector(tab: tab);
                        final total = _horizontal
                            ? cons.maxWidth
                            : cons.maxHeight;
                        final first = clampDouble(
                          total * _fraction,
                          160.0,
                          total - 160.0,
                        );
                        final divider = MouseRegion(
                          cursor: _horizontal
                              ? SystemMouseCursors.resizeColumn
                              : SystemMouseCursors.resizeRow,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanEnd: (_) => _saveLayout(),
                            onPanUpdate: (d) => setState(() {
                              final delta = _horizontal
                                  ? d.delta.dx
                                  : d.delta.dy;
                              _fraction = clampDouble(
                                (first + delta) / total,
                                0.2,
                                0.8,
                              );
                            }),
                            child: Container(
                              width: _horizontal ? 8 : null,
                              height: _horizontal ? null : 8,
                              alignment: Alignment.center,
                              child: Container(
                                width: _horizontal ? 1 : null,
                                height: _horizontal ? null : 1,
                                color: c.border,
                              ),
                            ),
                          ),
                        );
                        if (_horizontal) {
                          return Row(
                            children: <Widget>[
                              SizedBox(width: first, child: request),
                              divider,
                              Expanded(child: response),
                            ],
                          );
                        }
                        return Column(
                          children: <Widget>[
                            SizedBox(height: first, child: request),
                            divider,
                            Expanded(child: response),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });
  final RequestTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = tab.draft.displayName.isEmpty
        ? context.t('tabs.untitled')
        : tab.draft.displayName;
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220, minWidth: 100),
        padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
        decoration: BoxDecoration(
          color: active ? c.surfaceRaised : null,
          border: Border(
            bottom: BorderSide(
              color: active ? c.accent : Colors.transparent,
              width: 2,
            ),
            right: BorderSide(color: c.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              tab.draft.kind.name == 'http'
                  ? tab.draft.method
                  : (tab.draft.kind.name == 'sse' ? 'SSE' : 'WS'),
              style: context.methodBadge.copyWith(
                fontSize: 10,
                color: c.methodColor(tab.draft.method),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: context.body.copyWith(fontSize: 13),
              ),
            ),
            if (tab.dirty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.circle, size: 7, color: c.accent),
              ),
            IconButton(
              tooltip: context.t('common.close'),
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
