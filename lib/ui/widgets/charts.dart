import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';

/// Small, dependency-free charts drawn with [CustomPaint]. All of them are
/// laid out left-to-right (numbers and time axes do not mirror in RTL).

class ChartSlice {
  const ChartSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// Ring chart with a text in the middle and a legend underneath or beside it.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerText,
    this.centerCaption,
    this.size = 132,
    this.thickness = 18,
  });

  final List<ChartSlice> slices;
  final String centerText;
  final String? centerCaption;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = slices.where((s) => s.value > 0).toList();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CustomPaint(
                  size: Size.square(size),
                  painter: _DonutPainter(
                    slices: shown,
                    track: c.border.withAlpha(90),
                    thickness: thickness,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      centerText,
                      style: context.pageTitle.copyWith(fontSize: 20),
                    ),
                    if (centerCaption != null)
                      Text(centerCaption!, style: context.secondary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${s.label}  ${s.value.round()}',
                        style: context.secondary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.track,
    required this.thickness,
  });

  final List<ChartSlice> slices;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(thickness / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;
    var start = -math.pi / 2;
    const gap = 0.03;
    for (final s in slices) {
      final sweep = s.value / total * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.butt
        ..color = s.color;
      final g = slices.length > 1 ? gap : 0.0;
      canvas.drawArc(
        r,
        start + g / 2,
        math.max(0.001, sweep - g),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices || old.track != track || old.thickness != thickness;
}

/// Line with a soft filled area under it. [values] are plotted left to right.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 110,
    this.unit = '',
  });

  final List<double> values;
  final Color color;
  final double height;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _LinePainter(
                values: values,
                color: color,
                grid: c.border.withAlpha(110),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'max ${maxV.round()}$unit',
            style: context.secondary.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.color, required this.grid});

  final List<double> values;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) {
      if (values.length == 1) {
        canvas.drawCircle(
          Offset(size.width / 2, size.height / 2),
          4,
          Paint()..color = color,
        );
      }
      return;
    }
    final maxV = math.max(values.reduce(math.max), 1.0);
    const pad = 6.0;
    final h = size.height - pad * 2;
    Offset pt(int i) => Offset(
      size.width * i / (values.length - 1),
      pad + h - (values[i] / maxV) * h,
    );
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = pt(i - 1);
      final b = pt(i);
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[color.withAlpha(90), color.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawCircle(pt(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.color != color || old.grid != grid;
}

/// One row per label with a bar proportional to its value.
class BarList extends StatelessWidget {
  const BarList({
    super.key,
    required this.rows,
    this.valueText,
    this.labelWidth = 110,
  });

  final List<ChartSlice> rows;

  /// Formats the number shown at the end of a row. Default: rounded integer.
  final String Function(double v)? valueText;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxV = rows.isEmpty
        ? 1.0
        : math.max(rows.map((r) => r.value).reduce(math.max), 1.0);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: <Widget>[
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: labelWidth,
                    child: Text(
                      r.label,
                      style: context.mono.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, cons) => Stack(
                        children: <Widget>[
                          Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: c.border.withAlpha(90),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 10,
                            width: math.max(
                              4.0,
                              cons.maxWidth * r.value / maxV,
                            ),
                            decoration: BoxDecoration(
                              color: r.color,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      valueText?.call(r.value) ?? '${r.value.round()}',
                      textAlign: TextAlign.end,
                      style: context.timingStyle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A single bar split into coloured parts (for example passed / failed).
class StackedBar extends StatelessWidget {
  const StackedBar({super.key, required this.parts, this.height = 12});

  final List<ChartSlice> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = parts.fold<double>(0, (a, p) => a + p.value);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: total <= 0
              ? ColoredBox(color: c.border.withAlpha(90))
              : Row(
                  children: <Widget>[
                    for (final p in parts)
                      if (p.value > 0)
                        Expanded(
                          flex: math.max(1, (p.value / total * 1000).round()),
                          child: ColoredBox(color: p.color),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One phase of a request on the time axis.
class WaterfallPhase {
  const WaterfallPhase(this.label, this.duration, this.color);
  final String label;
  final Duration duration;
  final Color color;
}

/// Phases placed one after another on a shared time axis, so you can see
/// when each one started and how much of the total it took.
class Waterfall extends StatelessWidget {
  const Waterfall({
    super.key,
    required this.phases,
    required this.total,
    required this.format,
  });

  final List<WaterfallPhase> phases;
  final Duration total;
  final String Function(Duration d) format;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final totalUs = math.max(1, total.inMicroseconds);
    var offsetUs = 0;
    final rows = <Widget>[];
    for (final p in phases) {
      final start = offsetUs / totalUs;
      final width = (p.duration.inMicroseconds / totalUs).clamp(0.0, 1.0);
      offsetUs += p.duration.inMicroseconds;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 84,
                child: Text(
                  p.label,
                  style: context.secondary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final w = cons.maxWidth;
                    final barW = math.max(3.0, w * width);
                    final left = math.min(w * start, w - barW);
                    return SizedBox(
                      height: 14,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.border.withAlpha(60),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          Positioned(
                            left: left,
                            width: barW,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: p.color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  format(p.duration),
                  textAlign: TextAlign.end,
                  style: context.timingStyle,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: rows),
    );
  }
}
