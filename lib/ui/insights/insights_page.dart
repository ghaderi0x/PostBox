import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/format.dart';
import '../../features/history/application/history_cubit.dart';
import '../../features/history/domain/history_models.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';

/// Charts built from the request history: outcomes, latency and busiest
/// endpoints. Reads only what is already stored on this device.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  @override
  void initState() {
    super.initState();
    context.read<HistoryCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('insights.title'))),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          if (state.entries.isEmpty) {
            return EmptyState(
              icon: Icons.insights_outlined,
              title: context.t('insights.emptyTitle'),
              message: context.t('insights.emptyMsg'),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _Body(entries: state.entries),
            ),
          );
        },
      ),
    );
  }
}

/// Numbers derived from history entries (pure, so it can be unit tested).
class HistoryStats {
  HistoryStats(List<HistoryEntry> entries) {
    final sorted = <HistoryEntry>[...entries]..sort((a, b) => a.ts - b.ts);
    total = sorted.length;
    for (final e in sorted) {
      final st = e.status;
      if (e.error != null || st == null) {
        failed++;
      } else if (st >= 500) {
        s5xx++;
      } else if (st >= 400) {
        s4xx++;
      } else if (st >= 300) {
        s3xx++;
      } else if (st >= 200) {
        s2xx++;
      } else {
        s1xx++;
      }
      final d = e.durationMs;
      if (d != null) timed.add(d);
      methods[e.method] = (methods[e.method] ?? 0) + 1;
      final key = _endpoint(e);
      final bucket = perEndpoint.putIfAbsent(key, () => <int>[]);
      if (d != null) bucket.add(d);
    }
    latest = sorted.reversed
        .take(60)
        .toList()
        .reversed
        .where((e) => e.durationMs != null)
        .map((e) => e.durationMs!.toDouble())
        .toList();
  }

  late final int total;
  int s1xx = 0, s2xx = 0, s3xx = 0, s4xx = 0, s5xx = 0, failed = 0;
  final List<int> timed = <int>[];
  final Map<String, int> methods = <String, int>{};
  final Map<String, List<int>> perEndpoint = <String, List<int>>{};
  late final List<double> latest;

  int get ok => s2xx + s3xx + s1xx;

  double get successRate => total == 0 ? 0 : ok / total;

  double get averageMs =>
      timed.isEmpty ? 0 : timed.reduce((a, b) => a + b) / timed.length;

  double get p95Ms {
    if (timed.isEmpty) return 0;
    final s = <int>[...timed]..sort();
    final i = math.min(s.length - 1, (s.length * 0.95).ceil() - 1);
    return s[math.max(0, i)].toDouble();
  }

  /// Slowest endpoints by average time.
  List<MapEntry<String, double>> slowest([int n = 5]) {
    final rows = <MapEntry<String, double>>[
      for (final e in perEndpoint.entries)
        if (e.value.isNotEmpty)
          MapEntry<String, double>(
            e.key,
            e.value.reduce((a, b) => a + b) / e.value.length,
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return rows.take(n).toList();
  }

  static String _endpoint(HistoryEntry e) {
    final u = Uri.tryParse(e.url);
    if (u == null || u.host.isEmpty) return e.url;
    final path = u.path.isEmpty ? '/' : u.path;
    return '${u.host}$path';
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.entries});

  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fmt = Fmt(
      persianDigits: context.watch<SettingsCubit>().state.persianDigits,
    );
    final st = HistoryStats(entries);

    Widget stat(String label, String value, Color color) => Expanded(
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: context.secondary),
            const SizedBox(height: 6),
            Text(
              value,
              style: context.pageTitle.copyWith(fontSize: 22, color: color),
            ),
          ],
        ),
      ),
    );

    Widget card(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: context.sectionHeading),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );

    final methodRows =
        (st.methods.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(7)
            .map(
              (e) =>
                  ChartSlice(e.key, e.value.toDouble(), c.methodColor(e.key)),
            )
            .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            stat(
              context.t('insights.requests'),
              fmt.integer(st.total),
              c.textPrimary,
            ),
            const SizedBox(width: 10),
            stat(
              context.t('insights.success'),
              fmt.digits('${(st.successRate * 100).round()}%'),
              c.success,
            ),
            const SizedBox(width: 10),
            stat(
              context.t('insights.avg'),
              fmt.duration(Duration(milliseconds: st.averageMs.round())),
              c.accent,
            ),
            const SizedBox(width: 10),
            stat(
              'p95',
              fmt.duration(Duration(milliseconds: st.p95Ms.round())),
              c.warning,
            ),
          ],
        ),
        card(
          context.t('insights.outcomes'),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: <Widget>[
              DonutChart(
                centerText: fmt.integer(st.total),
                centerCaption: context.t('insights.requests'),
                slices: <ChartSlice>[
                  ChartSlice('2xx', (st.s2xx + st.s1xx).toDouble(), c.success),
                  ChartSlice('3xx', st.s3xx.toDouble(), c.methodPut),
                  ChartSlice('4xx', st.s4xx.toDouble(), c.warning),
                  ChartSlice('5xx', st.s5xx.toDouble(), c.danger),
                  ChartSlice(
                    context.t('insights.failedKind'),
                    st.failed.toDouble(),
                    c.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
        card(
          context.t('insights.latency'),
          LineChart(values: st.latest, color: c.accent, unit: ' ms'),
        ),
        card(
          context.t('insights.methods'),
          BarList(rows: methodRows, labelWidth: 70),
        ),
        if (st.slowest().isNotEmpty)
          card(
            context.t('insights.slowest'),
            BarList(
              labelWidth: 190,
              valueText: (v) => '${v.round()} ms',
              rows: <ChartSlice>[
                for (final e in st.slowest())
                  ChartSlice(e.key, e.value, c.accent),
              ],
            ),
          ),
      ],
    );
  }
}
