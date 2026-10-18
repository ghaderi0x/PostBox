import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/testing/domain/assertions.dart';
import '../../l10n/strings.dart';

class TestsEditor extends StatelessWidget {
  const TestsEditor({
    super.key,
    required this.assertions,
    required this.extractions,
    required this.onAssertions,
    required this.onExtractions,
  });

  final List<Assertion> assertions;
  final List<Extraction> extractions;
  final ValueChanged<List<Assertion>> onAssertions;
  final ValueChanged<List<Extraction>> onExtractions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Text(context.t('tests.assertions'), style: context.sectionHeading),
        const SizedBox(height: 4),
        Text(context.t('tests.assertionsHint'), style: context.secondary),
        const SizedBox(height: 8),
        for (final a in assertions)
          _AssertionRow(
            key: ValueKey<String>(a.id),
            a: a,
            onChanged: (n) => onAssertions(assertions.map((x) => x.id == n.id ? n : x).toList()),
            onDelete: () => onAssertions(assertions.where((x) => x.id != a.id).toList()),
          ),
        TextButton.icon(
          onPressed: () => onAssertions(<Assertion>[...assertions, Assertion.blank(AssertionKind.statusEquals)]),
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.t('tests.addAssertion')),
        ),
        const SizedBox(height: 18),
        Divider(color: c.border),
        const SizedBox(height: 10),
        Text(context.t('tests.extractions'), style: context.sectionHeading),
        const SizedBox(height: 4),
        Text(context.t('tests.extractionsHint'), style: context.secondary),
        const SizedBox(height: 8),
        for (final e in extractions)
          _ExtractionRow(
            key: ValueKey<String>(e.id),
            e: e,
            onChanged: (n) => onExtractions(extractions.map((x) => x.id == n.id ? n : x).toList()),
            onDelete: () => onExtractions(extractions.where((x) => x.id != e.id).toList()),
          ),
        TextButton.icon(
          onPressed: () => onExtractions(<Extraction>[...extractions, Extraction.blank()]),
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.t('tests.addExtraction')),
        ),
      ],
    );
  }
}

class _AssertionRow extends StatefulWidget {
  const _AssertionRow({super.key, required this.a, required this.onChanged, required this.onDelete});
  final Assertion a;
  final ValueChanged<Assertion> onChanged;
  final VoidCallback onDelete;

  @override
  State<_AssertionRow> createState() => _AssertionRowState();
}

class _AssertionRowState extends State<_AssertionRow> {
  late final TextEditingController _target = TextEditingController(text: widget.a.target);
  late final TextEditingController _expected = TextEditingController(text: widget.a.expected);

  @override
  void dispose() {
    _target.dispose();
    _expected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<AssertionKind>(
              initialValue: a.kind,
              isExpanded: true,
              items: <DropdownMenuItem<AssertionKind>>[
                for (final k in AssertionKind.values)
                  DropdownMenuItem<AssertionKind>(value: k, child: Text(context.t('tests.kind.${k.name}'), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (k) {
                if (k != null) widget.onChanged(a.copyWith(kind: k));
              },
            ),
          ),
          if (a.usesTarget)
            SizedBox(
              width: 170,
              child: TextField(
                controller: _target,
                style: context.mono,
                decoration: InputDecoration(
                  hintText: a.kind == AssertionKind.jsonPathEquals || a.kind == AssertionKind.jsonPathExists
                      ? r'$.data.id'
                      : 'Content-Type',
                ),
                onChanged: (v) => widget.onChanged(a.copyWith(target: v)),
              ),
            ),
          if (a.usesExpected)
            SizedBox(
              width: 170,
              child: TextField(
                controller: _expected,
                style: context.mono,
                decoration: InputDecoration(hintText: context.t('tests.expected')),
                onChanged: (v) => widget.onChanged(a.copyWith(expected: v)),
              ),
            ),
          IconButton(
            tooltip: context.t('common.delete'),
            icon: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

class _ExtractionRow extends StatefulWidget {
  const _ExtractionRow({super.key, required this.e, required this.onChanged, required this.onDelete});
  final Extraction e;
  final ValueChanged<Extraction> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ExtractionRow> createState() => _ExtractionRowState();
}

class _ExtractionRowState extends State<_ExtractionRow> {
  late final TextEditingController _name = TextEditingController(text: widget.e.variable);
  late final TextEditingController _expr = TextEditingController(text: widget.e.expression);

  @override
  void dispose() {
    _name.dispose();
    _expr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: TextField(
              controller: _name,
              style: context.mono,
              decoration: InputDecoration(hintText: context.t('tests.variable')),
              onChanged: (v) => widget.onChanged(e.copyWith(variable: v)),
            ),
          ),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<ExtractionSource>(
              initialValue: e.source,
              isExpanded: true,
              items: <DropdownMenuItem<ExtractionSource>>[
                DropdownMenuItem<ExtractionSource>(
                    value: ExtractionSource.jsonPath, child: Text(context.t('tests.src.jsonPath'))),
                DropdownMenuItem<ExtractionSource>(
                    value: ExtractionSource.header, child: Text(context.t('tests.src.header'))),
              ],
              onChanged: (s) {
                if (s != null) widget.onChanged(e.copyWith(source: s));
              },
            ),
          ),
          SizedBox(
            width: 190,
            child: TextField(
              controller: _expr,
              style: context.mono,
              decoration: InputDecoration(
                hintText: e.source == ExtractionSource.jsonPath ? r'$.token' : 'X-Request-Id',
              ),
              onChanged: (v) => widget.onChanged(e.copyWith(expression: v)),
            ),
          ),
          IconButton(
            tooltip: context.t('common.delete'),
            icon: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
