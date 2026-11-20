import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/json_util.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';

/// Collapsible tree of a JSON document. Children are built only when a node
/// is expanded and long lists are paged, so large responses stay responsive.
/// Every node can copy its value or its path.
class JsonTreeView extends StatefulWidget {
  const JsonTreeView({super.key, required this.text});

  final String text;

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<JsonTreeView> {
  Object? _root;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(JsonTreeView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _parse();
  }

  void _parse() {
    try {
      _root = jsonDecode(widget.text);
      _ok = true;
    } on FormatException {
      _root = null;
      _ok = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ok) {
      return Center(
        child: Text(context.t('resp.treeInvalid'), style: context.secondary),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: <Widget>[
        _TreeNode(
          label: null,
          value: _root,
          path: const <Object>[],
          depth: 0,
          initiallyOpen: true,
        ),
      ],
    );
  }
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({
    required this.label,
    required this.value,
    required this.path,
    required this.depth,
    this.initiallyOpen = false,
  });

  final Object? label;
  final Object? value;
  final List<Object> path;
  final int depth;
  final bool initiallyOpen;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  static const int _page = 100;
  late bool _open = widget.initiallyOpen;
  int _shown = _page;

  bool get _isContainer => widget.value is Map || widget.value is List;

  int get _count {
    final v = widget.value;
    if (v is Map) return v.length;
    if (v is List) return v.length;
    return 0;
  }

  Widget _valueText(BuildContext context) {
    final c = context.colors;
    final v = widget.value;
    if (v is Map) {
      return Text('{$_count}', style: context.mono.copyWith(color: c.synPunct));
    }
    if (v is List) {
      return Text('[$_count]', style: context.mono.copyWith(color: c.synPunct));
    }
    if (v is String) {
      final shown = v.length > 200 ? '${v.substring(0, 200)}…' : v;
      return Flexible(
        child: Text(
          '"$shown"',
          style: context.mono.copyWith(color: c.synString),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (v is num) {
      return Text('$v', style: context.mono.copyWith(color: c.synNumber));
    }
    return Text('$v', style: context.mono.copyWith(color: c.synLiteral));
  }

  String _copyValue() {
    final v = widget.value;
    if (v is String) return v;
    return const JsonEncoder.withIndent('  ').convert(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = widget.label;
    final indent = 14.0 * widget.depth;
    final row = Pressable(
      onTap: _isContainer ? () => setState(() => _open = !_open) : null,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: indent + 4,
          end: 2,
          top: 1,
          bottom: 1,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 18,
              child: _isContainer
                  ? Icon(
                      _open ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: c.textSecondary,
                    )
                  : null,
            ),
            if (label != null)
              Text(
                label is int ? '[$label]' : '$label',
                style: context.mono.copyWith(
                  color: label is int ? c.textSecondary : c.synKey,
                ),
              ),
            if (label != null)
              Text(': ', style: context.mono.copyWith(color: c.synPunct)),
            _valueText(context),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: context.t('common.more'),
              iconSize: 16,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz, size: 16, color: c.textSecondary),
              onSelected: (v) {
                if (v == 'value') copyText(context, _copyValue());
                if (v == 'path') copyText(context, jsonPathFor(widget.path));
              },
              itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'value',
                  child: Text(ctx.t('resp.copyValue')),
                ),
                PopupMenuItem<String>(
                  value: 'path',
                  child: Text(ctx.t('resp.copyPath')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!_isContainer || !_open) return row;

    final v = widget.value;
    final children = <Widget>[];
    if (v is Map) {
      final entries = v.entries.toList();
      for (final e in entries.take(_shown)) {
        children.add(
          _TreeNode(
            label: e.key,
            value: e.value,
            path: <Object>[...widget.path, '${e.key}'],
            depth: widget.depth + 1,
          ),
        );
      }
    } else if (v is List) {
      for (var i = 0; i < v.length && i < _shown; i++) {
        children.add(
          _TreeNode(
            label: i,
            value: v[i],
            path: <Object>[...widget.path, i],
            depth: widget.depth + 1,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        row,
        ...children,
        if (_count > _shown)
          Padding(
            padding: EdgeInsetsDirectional.only(start: indent + 28),
            child: TextButton(
              onPressed: () => setState(() => _shown += _page),
              child: Text(
                context.t('resp.showMore', <String>['${_count - _shown}']),
              ),
            ),
          ),
      ],
    );
  }
}
