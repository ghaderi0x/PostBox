import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../l10n/strings.dart';
import '../../core/util/json_util.dart';

class PaletteItem {
  const PaletteItem({
    required this.label,
    required this.icon,
    required this.run,
    this.hint = '',
  });
  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback run;
}

/// Ctrl+K command palette: type to filter, arrows to move, Enter to run.
Future<void> showCommandPalette(BuildContext context, List<PaletteItem> items) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: _Palette(items: items),
      ),
    ),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.items});
  final List<PaletteItem> items;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final TextEditingController _q = TextEditingController();
  int _index = 0;

  List<PaletteItem> get _filtered {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where((i) => '${i.label} ${i.hint}'.toLowerCase().contains(q))
        .toList();
  }

  void _run(PaletteItem i) {
    Navigator.pop(context);
    i.run();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _filtered;
    final idx = list.isEmpty ? 0 : clampInt(_index, 0, list.length - 1);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
          () =>
              _index = clampInt(idx + 1, 0, list.isEmpty ? 0 : list.length - 1),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(
          () =>
              _index = clampInt(idx - 1, 0, list.isEmpty ? 0 : list.length - 1),
        ),
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.t('palette.hint'),
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: (_) => setState(() => _index = 0),
              onSubmitted: (_) {
                if (list.isNotEmpty) _run(list[idx]);
              },
            ),
          ),
          Flexible(
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      context.t('palette.none'),
                      style: context.secondary,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) => ListTile(
                      dense: true,
                      selected: i == idx,
                      selectedTileColor: c.accent.withAlpha(30),
                      leading: Icon(list[i].icon, size: 18),
                      title: Text(
                        list[i].label,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: list[i].hint.isEmpty
                          ? null
                          : Text(list[i].hint, overflow: TextOverflow.ellipsis),
                      onTap: () => _run(list[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
