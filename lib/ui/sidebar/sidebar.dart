import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../l10n/strings.dart';
import 'collections_panel.dart';
import 'history_panel.dart';

/// Collections and History switcher used by both layouts.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, this.onOpened});
  final VoidCallback? onOpened;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(context.t('nav.collections')),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(context.t('nav.history')),
                ),
              ],
              selected: <int>{_index},
              onSelectionChanged: (s) => setState(() => _index = s.first),
            ),
          ),
        ),
        Divider(color: c.border, height: 12),
        Expanded(
          child: _index == 0
              ? CollectionsPanel(onOpened: widget.onOpened)
              : HistoryPanel(onOpened: widget.onOpened),
        ),
      ],
    );
  }
}
