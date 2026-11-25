import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/file_service.dart';
import '../../core/util/format.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/runner/application/runner_cubit.dart';
import '../../features/runner/domain/run_data.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';

class RunnerPage extends StatefulWidget {
  const RunnerPage({super.key, required this.collectionId});
  final String collectionId;

  @override
  State<RunnerPage> createState() => _RunnerPageState();
}

class _RunnerPageState extends State<RunnerPage> {
  bool _stopOnFailure = false;
  int _iterations = 1;
  int _concurrency = 1;
  RunData? _data;
  final TextEditingController _iterationsCtl = TextEditingController(text: '1');

  @override
  void dispose() {
    _iterationsCtl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final files = context.read<FileService>();
    final picked = await files.pickFile(
      extensions: <String>['csv', 'tsv', 'json', 'txt'],
    );
    if (picked == null) return;
    try {
      final text = await files.readText(
        picked.path,
        maxBytes: kMaxRunDataBytes,
      );
      final data = parseRunData(text);
      if (mounted) setState(() => _data = data);
    } on RunDataException catch (e) {
      if (mounted) {
        await showToast(context, context.t('runner.dataError.${e.code}'));
      }
    } on FileTooLargeException {
      if (mounted) {
        await showToast(context, context.t('runner.dataError.too_large'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = context.read<CollectionsCubit>().state.collection(
      widget.collectionId,
    );
    final settings = context.watch<SettingsCubit>().state;
    final fmt = Fmt(persianDigits: settings.persianDigits);
    final total = context
        .read<RunnerCubit>()
        .requestsOf(widget.collectionId)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('runner.title', <String>[col?.name ?? ''])),
      ),
      body: BlocBuilder<RunnerCubit, RunnerState>(
        builder: (context, s) {
          final cubit = context.read<RunnerCubit>();
          final sameRun = s.collectionName == col?.name;
          // The settings block scrolls away with the results and returns as
          // soon as you scroll up.
          return NestedScrollView(
            floatHeaderSlivers: true,
            headerSliverBuilder: (context, innerBoxIsScrolled) => <Widget>[
              SliverToBoxAdapter(
                child: Column(
                  children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    InfoBanner(
                      context.t('runner.info', <String>[fmt.integer(total)]),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.t('runner.stopOnFailure')),
                      value: _stopOnFailure,
                      onChanged: s.running
                          ? null
                          : (v) => setState(() => _stopOnFailure = v),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 110,
                          child: TextField(
                            enabled: !s.running && _data == null,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.t('runner.iterations'),
                            ),
                            controller: _iterationsCtl,
                            onChanged: (v) => _iterations =
                                (int.tryParse(v) ?? 1).clamp(1, 1000),
                          ),
                        ),
                        DropdownButton<int>(
                          value: _concurrency,
                          onChanged: s.running
                              ? null
                              : (v) => setState(() => _concurrency = v ?? 1),
                          items: <DropdownMenuItem<int>>[
                            for (final n in const <int>[1, 2, 4, 8])
                              DropdownMenuItem<int>(
                                value: n,
                                child: Text(
                                  context.t('runner.parallel', <String>['$n']),
                                ),
                              ),
                          ],
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.table_chart_outlined,
                            size: 16,
                          ),
                          label: Text(context.t('runner.loadData')),
                          onPressed: s.running ? null : _loadData,
                        ),
                        if (_data != null)
                          InputChip(
                            label: Text(
                              context.t('runner.dataLoaded', <String>[
                                '${_data!.rows.length}',
                                _data!.columns.take(4).join(', '),
                              ]),
                            ),
                            onDeleted: s.running
                                ? null
                                : () => setState(() => _data = null),
                          ),
                      ],
                    ),
                    if (_concurrency > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          context.t('runner.parallelHint'),
                          style: context.secondary,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        if (s.running)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.danger,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onError,
                            ),
                            onPressed: cubit.stop,
                            icon: const Icon(Icons.stop, size: 18),
                            label: Text(context.t('runner.stop')),
                          )
                        else
                          FilledButton.icon(
                            onPressed: total == 0
                                ? null
                                : () => cubit.run(
                                    widget.collectionId,
                                    stopOnFailure: _stopOnFailure,
                                    iterations: _iterations,
                                    concurrency: _concurrency,
                                    data:
                                        _data?.rows ??
                                        const <Map<String, String>>[],
                                  ),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text(context.t('runner.run')),
                          ),
                        const SizedBox(width: 12),
                        if (sameRun && s.results.isNotEmpty)
                          Expanded(
                            child: Text(
                              context.t('runner.summary', <String>[
                                fmt.integer(s.passed),
                                fmt.integer(s.failed),
                                fmt.integer(s.total),
                              ]),
                              style: context.body,
                            ),
                          ),
                      ],
                    ),
                    if (s.running) ...<Widget>[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: s.total == 0 ? null : s.results.length / s.total,
                      ),
                    ],
                  ],
                ),
              ),
              Divider(color: c.border, height: 1),
                  ],
                ),
              ),
            ],
            body: Column(
              children: <Widget>[
              Expanded(
                child: !sameRun || s.results.isEmpty
                    ? EmptyState(
                        icon: Icons.play_circle_outline,
                        title: context.t('runner.emptyTitle'),
                        message: context.t('runner.emptyMsg'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: s.results.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          if (i == 0) return _RunCharts(state: s);
                          final r = s.results[i - 1];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                r.passed
                                    ? Icons.check_circle_outline
                                    : Icons.cancel_outlined,
                                size: 20,
                                color: r.passed ? c.success : c.danger,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        if (s.iterations > 1)
                                          Padding(
                                            padding:
                                                const EdgeInsetsDirectional.only(
                                                  end: 6,
                                                ),
                                            child: Text(
                                              '#${r.iteration + 1}',
                                              style: ctx.timingStyle,
                                            ),
                                          ),
                                        MethodBadge(r.method, width: 48),
                                        Expanded(
                                          child: Text(
                                            r.name,
                                            style: ctx.body.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      r.url,
                                      style: ctx.mono.copyWith(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.ltr,
                                    ),
                                    Wrap(
                                      spacing: 10,
                                      children: <Widget>[
                                        if (r.status != null)
                                          Text(
                                            fmt.integer(r.status!),
                                            style: ctx
                                                .statusStyle(r.status!)
                                                .copyWith(fontSize: 12),
                                          ),
                                        if (r.durationMs != null)
                                          Text(
                                            fmt.duration(
                                              Duration(
                                                milliseconds: r.durationMs!,
                                              ),
                                            ),
                                            style: ctx.timingStyle,
                                          ),
                                        if (r.error != null)
                                          Text(
                                            ctx.t(
                                              r.error == 'script'
                                                  ? 'err.script.pre'
                                                  : (r.error!.contains('_')
                                                        ? 'err.build.${r.error}'
                                                        : 'err.http.${r.error}'),
                                            ),
                                            style: ctx.timingStyle.copyWith(
                                              color: c.danger,
                                            ),
                                          ),
                                      ],
                                    ),
                                    for (final t in r.scriptTests.where(
                                      (t) => !t.passed,
                                    ))
                                      Text(
                                        '${ctx.t('runner.scriptTest')}: ${t.name}',
                                        style: ctx.secondary.copyWith(
                                          color: c.danger,
                                        ),
                                      ),
                                    for (final a in r.assertions.where(
                                      (a) => !a.passed,
                                    ))
                                      Text(
                                        '${ctx.t('tests.kind.${a.assertion.kind.name}')}: ${a.message}',
                                        style: ctx.secondary.copyWith(
                                          color: c.danger,
                                        ),
                                      ),
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
                  child: Wrap(
                    spacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () => showTextDialog(
                          context,
                          title: context.t('runner.reportMd'),
                          text: s.toMarkdown(),
                        ),
                        child: Text(context.t('runner.reportMd')),
                      ),
                      OutlinedButton(
                        onPressed: () => showTextDialog(
                          context,
                          title: context.t('runner.reportJson'),
                          text: s.toJsonString(),
                        ),
                        child: Text(context.t('runner.reportJson')),
                      ),
                    ],
                  ),
                ),
            ],
            ),
          );
        },
      ),
    );
  }
}

/// Pass/fail split and time per request for the finished (or running) run.
class _RunCharts extends StatelessWidget {
  const _RunCharts({required this.state});

  final RunnerState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fmt = Fmt(
      persianDigits: context.watch<SettingsCubit>().state.persianDigits,
    );
    final timed = state.results
        .where((r) => r.durationMs != null)
        .toList(growable: false);
    final slowest = <RunResult>[...timed]
      ..sort((a, b) => b.durationMs!.compareTo(a.durationMs!));
    final top = slowest.take(5).toList();
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.t('chart.runResults'), style: context.sectionHeading),
          const SizedBox(height: 10),
          StackedBar(
            parts: <ChartSlice>[
              ChartSlice(context.t('chart.passed'), state.passed.toDouble(), c.success),
              ChartSlice(context.t('chart.failed'), state.failed.toDouble(), c.danger),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${context.t('chart.passed')} ${fmt.integer(state.passed)}  ·  '
            '${context.t('chart.failed')} ${fmt.integer(state.failed)}',
            style: context.secondary,
          ),
          if (top.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(context.t('chart.slowest'), style: context.sectionHeading),
            const SizedBox(height: 6),
            BarList(
              rows: <ChartSlice>[
                for (final r in top)
                  ChartSlice(
                    '${r.method} ${r.name}',
                    r.durationMs!.toDouble(),
                    r.passed ? c.accent : c.danger,
                  ),
              ],
              valueText: (v) => '${v.round()} ms',
              labelWidth: 130,
            ),
          ],
        ],
      ),
    );
  }
}
