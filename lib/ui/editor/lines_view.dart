import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/json_util.dart';

/// Read-only, virtualized viewer for large text. Builds only visible lines,
/// so memory and frame time stay bounded. No highlighting or wrapping.
class LinesView extends StatefulWidget {
  const LinesView({
    super.key,
    required this.text,
    this.query = '',
    this.focusLine,
  });

  final String text;

  /// Lines containing this text get a tinted background.
  final String query;

  /// Zero-based line to scroll to when it changes.
  final int? focusLine;

  @override
  State<LinesView> createState() => _LinesViewState();
}

class _LinesViewState extends State<LinesView> {
  late List<int> _starts;
  final ScrollController _v = ScrollController();
  final ScrollController _h = ScrollController();
  double _lineH = 18;

  @override
  void initState() {
    super.initState();
    _index();
  }

  void _index() {
    final t = widget.text;
    final starts = <int>[0];
    var i = t.indexOf('\n');
    while (i >= 0) {
      starts.add(i + 1);
      i = t.indexOf('\n', i + 1);
    }
    _starts = starts;
  }

  @override
  void didUpdateWidget(LinesView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _index();
    if (widget.focusLine != null &&
        widget.focusLine != old.focusLine &&
        _v.hasClients) {
      final y = widget.focusLine! * _lineH;
      _v.jumpTo(clampDouble(y, 0.0, _v.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  String _line(int i) {
    final s = _starts[i];
    var e = i + 1 < _starts.length ? _starts[i + 1] - 1 : widget.text.length;
    if (e > s && widget.text.codeUnitAt(e - 1) == 13) e--;
    final line = widget.text.substring(s, e);
    // Avoid huge single lines freezing layout.
    return line.length > 4000 ? '${line.substring(0, 4000)}…' : line;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.codeStyle;
    final probe = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _lineH = probe.height;
    final charW = probe.width;
    probe.dispose();
    final digits = '${_starts.length}'.length;
    final gutterW = digits * charW + 16;
    final q = widget.query.toLowerCase();

    // Code and its line numbers always run left to right. Without this, a
    // right-to-left UI (Persian) starts the horizontal scroller at its far
    // end, so the numbers sit outside the visible area and look broken.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, cons) {
          final contentW = math.max(cons.maxWidth - gutterW, 2000.0);
          return Scrollbar(
            controller: _v,
            child: SingleChildScrollView(
              controller: _h,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentW + gutterW,
                child: ListView.builder(
                  controller: _v,
                  itemCount: _starts.length,
                  itemExtent: _lineH,
                  itemBuilder: (ctx, i) {
                    final line = _line(i);
                    final hit = q.isNotEmpty && line.toLowerCase().contains(q);
                    return Container(
                      color: hit ? c.accent.withAlpha(40) : null,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        children: <Widget>[
                          SizedBox(
                            width: gutterW,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                '${i + 1}',
                                textAlign: TextAlign.right,
                                style: style.copyWith(color: c.textSecondary),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line,
                              style: style,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
