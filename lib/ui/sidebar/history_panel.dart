import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/format.dart';
import '../../core/util/ids.dart';
import '../../features/history/application/history_cubit.dart';
import '../../features/history/domain/history_models.dart';
import '../../features/requests/domain/request_models.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, this.onOpened});
  final VoidCallback? onOpened;

  void _replay(BuildContext context, HistoryEntry e) {
    RequestModel model;
    final raw = e.requestJson;
    if (raw != null) {
      try {
        model = RequestModel.fromJson(jsonDecode(raw)).copyWith(id: newId());
      } on FormatException {
        model = RequestModel(id: newId(), method: e.method, url: e.url);
      }
    } else {
      model = RequestModel(id: newId(), method: e.method, url: e.url);
    }
    context.read<WorkspaceCubit>().newTab(model: model);
    onOpened?.call();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final fmt = Fmt(persianDigits: settings.persianDigits, jalali: settings.jalaliDates);
    final c = context.colors;
    return BlocBuilder<HistoryCubit, HistoryState>(builder: (context, s) {
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      onChanged: context.read<HistoryCubit>().setQuery,
                      decoration: InputDecoration(
                        hintText: context.t('history.search'),
                        prefixIcon: const Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.t('history.clear'),
                  icon: Icon(Icons.delete_sweep_outlined, color: c.textSecondary),
                  onPressed: s.entries.isEmpty
                      ? null
                      : () async {
                          final ok = await confirmDestructive(
                            context,
                            title: context.t('history.clearTitle'),
                            message: context.t('history.clearMsg'),
                            confirmLabel: context.t('history.clear'),
                          );
                          if (ok && context.mounted) context.read<HistoryCubit>().clear();
                        },
                ),
              ],
            ),
          ),
          if (!settings.persistHistory)
            Padding(
              padding: const EdgeInsets.all(10),
              child: InfoBanner(context.t('history.off')),
            ),
          Expanded(
            child: s.entries.isEmpty
                ? EmptyState(
                    icon: Icons.history,
                    title: context.t('history.emptyTitle'),
                    message: context.t('history.emptyMsg'),
                  )
                : ListView.builder(
                    itemCount: s.entries.length,
                    itemBuilder: (ctx, i) {
                      final e = s.entries[i];
                      return InkWell(
                        onTap: () => _replay(ctx, e),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              MethodBadge(e.method, width: 46),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(e.url, maxLines: 2, overflow: TextOverflow.ellipsis, style: ctx.mono.copyWith(fontSize: 12.5), textDirection: TextDirection.ltr),
                                    const SizedBox(height: 2),
                                    Wrap(spacing: 10, children: <Widget>[
                                      if (e.status != null)
                                        Text(fmt.integer(e.status!), style: ctx.statusStyle(e.status!).copyWith(fontSize: 12)),
                                      if (e.error != null)
                                        Text(ctx.t('err.http.${e.error}'), style: ctx.timingStyle.copyWith(color: c.danger)),
                                      if (e.durationMs != null)
                                        Text(fmt.duration(Duration(milliseconds: e.durationMs!)), style: ctx.timingStyle),
                                      Text(fmt.dateTime(DateTime.fromMillisecondsSinceEpoch(e.ts)), style: ctx.timingStyle),
                                    ]),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_horiz, size: 18, color: c.textSecondary),
                                padding: EdgeInsets.zero,
                                onSelected: (v) {
                                  if (v == 'replay') _replay(ctx, e);
                                  if (v == 'delete') ctx.read<HistoryCubit>().delete(e.id);
                                },
                                itemBuilder: (_) => <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(value: 'replay', child: Text(ctx.t('history.replay'))),
                                  PopupMenuItem<String>(value: 'delete', child: Text(ctx.t('common.delete'))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}
