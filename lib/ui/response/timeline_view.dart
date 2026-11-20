import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/format.dart';
import '../../features/http/domain/http_engine.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// Timing breakdown, protocol and server certificate of a response.
class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.result});

  final HttpResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fmt = Fmt(
      persianDigits: context.watch<SettingsCubit>().state.persianDigits,
    );
    final t = result.timings;
    final total = result.duration.inMicroseconds <= 0
        ? 1
        : result.duration.inMicroseconds;

    Widget bar(String labelKey, Duration d, Color color) {
      final fraction = (d.inMicroseconds / total).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 150,
              child: Text(context.t(labelKey), style: context.body),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: c.border.withAlpha(90),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction == 0 ? 0.004 : fraction,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                fmt.duration(d),
                style: context.timingStyle,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
    }

    final tls = result.tls;
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Text(context.t('resp.timeline'), style: context.sectionHeading),
        const SizedBox(height: 6),
        if (t.redirects > Duration.zero)
          bar('resp.t.redirects', t.redirects, c.warning),
        bar('resp.t.connect', t.connect, c.accent),
        bar('resp.t.wait', t.wait, c.synNumber),
        bar('resp.t.download', t.download, c.success),
        const Divider(height: 18),
        Row(
          children: <Widget>[
            SizedBox(
              width: 150,
              child: Text(
                context.t('resp.t.total'),
                style: context.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(fmt.duration(result.duration), style: context.timingStyle),
          ],
        ),
        const SizedBox(height: 16),
        Text(context.t('chart.waterfall'), style: context.sectionHeading),
        const SizedBox(height: 6),
        Waterfall(
          total: result.duration,
          format: fmt.duration,
          phases: <WaterfallPhase>[
            if (t.redirects > Duration.zero)
              WaterfallPhase(
                context.t('resp.t.redirects'),
                t.redirects,
                c.warning,
              ),
            WaterfallPhase(context.t('resp.t.connect'), t.connect, c.accent),
            WaterfallPhase(context.t('resp.t.wait'), t.wait, c.synNumber),
            WaterfallPhase(context.t('resp.t.download'), t.download, c.success),
          ],
        ),
        const SizedBox(height: 8),
        Text(context.t('resp.timingNote'), style: context.secondary),
        const SizedBox(height: 18),
        Text(context.t('resp.protocol'), style: context.sectionHeading),
        const SizedBox(height: 4),
        Text(
          result.protocol == 'h2' ? 'HTTP/2' : 'HTTP/1.1',
          style: context.mono,
        ),
        const SizedBox(height: 18),
        Text(context.t('resp.certificate'), style: context.sectionHeading),
        const SizedBox(height: 4),
        if (tls == null)
          Text(context.t('resp.noTls'), style: context.secondary)
        else ...<Widget>[
          if (tls.isExpiredAt(now))
            InfoBanner(context.t('resp.certExpired'), warning: true),
          _kv(context, context.t('resp.certSubject'), tls.subject),
          _kv(context, context.t('resp.certIssuer'), tls.issuer),
          _kv(
            context,
            context.t('resp.certValid'),
            '${_date(tls.validFrom)}  →  ${_date(tls.validTo)}',
          ),
          _kv(context, 'SHA-1', tls.sha1),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(context.t('resp.copyCert')),
              onPressed: tls.pem.isEmpty
                  ? null
                  : () => copyText(context, tls.pem),
            ),
          ),
        ],
      ],
    );
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 110, child: Text(k, style: context.secondary)),
        Expanded(
          child: SelectableText(v, style: context.mono.copyWith(fontSize: 12)),
        ),
      ],
    ),
  );
}
