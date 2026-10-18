import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/format.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/runner/application/runner_cubit.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

class RunnerPage extends StatefulWidget {
  const RunnerPage({super.key, required this.collectionId});
  final String collectionId;

  @override
  State<RunnerPage> createState() => _RunnerPageState();
}

class _RunnerPageState extends State<RunnerPage> {
  bool _stopOnFailure = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = context.read<CollectionsCubit>().state.collection(widget.collectionId);
    final settings = context.watch<SettingsCubit>().state;
    final fmt = Fmt(persianDigits: settings.persianDigits);
    final total = context.read<RunnerCubit>().requestsOf(widget.collectionId).length;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('runner.title', <String>[col?.name ?? '']))),
      body: BlocBuilder<RunnerCubit, RunnerState>(builder: (context, s) {
        final cubit = context.read<RunnerCubit>();
        final sameRun = s.collectionName == col?.name;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  InfoBanner(context.t('runner.info', <String>[fmt.integer(total)])),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.t('runner.stopOnFailure')),
                    value: _stopOnFailure,
                    onChanged: s.running ? null : (v) => setState(() => _stopOnFailure = v),
                  ),
                  Row(children: <Widget>[
                    if (s.running)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.danger,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                        onPressed: cubit.stop,
                        icon: const Icon(Icons.stop, size: 18),
                        label: Text(context.t('runner.stop')),
                      )
                    else
                      FilledButton.icon(
                        onPressed: total == 0 ? null : () => cubit.run(widget.collectionId, stopOnFailure: _stopOnFailure),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(context.t('runner.run')),
                      ),
                    const SizedBox(width: 12),
                    if (sameRun && s.results.isNotEmpty)
                      Expanded(
                        child: Text(
                          context.t('runner.summary', <String>[fmt.integer(s.passed), fmt.integer(s.failed), fmt.integer(s.total)]),
                          style: context.body,
                        ),
                      ),
                  ]),
                  if (s.running) ...<Widget>[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: s.total == 0 ? null : s.results.length / s.total),
                  ],
                ],
              ),
            ),
            Divider(color: c.border, height: 1),
            Expanded(
              child: !sameRun || s.results.isEmpty
                  ? EmptyState(icon: Icons.play_circle_outline, title: context.t('runner.emptyTitle'), message: context.t('runner.emptyMsg'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: s.results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final r = s.results[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(r.passed ? Icons.check_circle_outline : Icons.cancel_outlined, size: 20, color: r.passed ? c.success : c.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(children: <Widget>[
                                    MethodBadge(r.method, width: 48),
                                    Expanded(child: Text(r.name, style: ctx.body.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                  ]),
                                  Text(r.url, style: ctx.mono.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                                  Wrap(spacing: 10, children: <Widget>[
                                    if (r.status != null) Text(fmt.integer(r.status!), style: ctx.statusStyle(r.status!).copyWith(fontSize: 12)),
                                    if (r.durationMs != null) Text(fmt.duration(Duration(milliseconds: r.durationMs!)), style: ctx.timingStyle),
                                    if (r.error != null) Text(ctx.t(r.error!.contains('_') ? 'err.build.${r.error}' : 'err.http.${r.error}'), style: ctx.timingStyle.copyWith(color: c.danger)),
                                  ]),
                                  for (final a in r.assertions.where((a) => !a.passed))
                                    Text('${ctx.t('tests.kind.${a.assertion.kind.name}')}: ${a.message}', style: ctx.secondary.copyWith(color: c.danger)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (sameRun && s.results.isNotEmpty && !s.running)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(spacing: 8, children: <Widget>[
                  OutlinedButton(
                    onPressed: () => showTextDialog(context, title: context.t('runner.reportMd'), text: s.toMarkdown()),
                    child: Text(context.t('runner.reportMd')),
                  ),
                  OutlinedButton(
                    onPressed: () => showTextDialog(context, title: context.t('runner.reportJson'), text: s.toJsonString()),
                    child: Text(context.t('runner.reportJson')),
                  ),
                ]),
              ),
          ],
        );
      }),
    );
  }
}
