import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/collections/domain/collection_models.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

class SaveTarget {
  const SaveTarget({required this.collectionId, required this.parentId, required this.name});
  final String collectionId;
  final String? parentId;
  final String name;
}

/// Lets the user pick a collection and folder for a new saved request.
Future<SaveTarget?> showSaveRequestDialog(
  BuildContext context, {
  required String initialName,
  String? preferredCollectionId,
  String titleKey = 'save.title',
  String confirmKey = 'common.save',
  bool askName = true,
}) {
  return showDialog<SaveTarget>(
    context: context,
    builder: (ctx) => _SaveDialog(
      initialName: initialName,
      preferredCollectionId: preferredCollectionId,
      titleKey: titleKey,
      confirmKey: confirmKey,
      askName: askName,
    ),
  );
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({
    required this.initialName,
    this.preferredCollectionId,
    required this.titleKey,
    required this.confirmKey,
    required this.askName,
  });
  final String initialName;
  final String? preferredCollectionId;
  final String titleKey;
  final String confirmKey;
  final bool askName;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  String? _collectionId;
  String? _parentId;

  @override
  void initState() {
    super.initState();
    final cols = context.read<CollectionsCubit>().state.collections;
    if (cols.isNotEmpty) {
      _collectionId = cols.any((c) => c.id == widget.preferredCollectionId)
          ? widget.preferredCollectionId
          : cols.first.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<(NodeRecord, int)> _folders(CollectionsState s) {
    final out = <(NodeRecord, int)>[];
    void walk(String? parent, int depth) {
      for (final n in s.childrenOf(_collectionId!, parent)) {
        if (n.isFolder) {
          out.add((n, depth));
          walk(n.id, depth + 1);
        }
      }
    }

    if (_collectionId != null) walk(null, 0);
    return out;
  }

  Future<void> _newCollection() async {
    final name = await promptText(context, title: context.t('collections.new'), label: context.t('common.name'));
    if (name == null || name.trim().isEmpty || !mounted) return;
    final c = await context.read<CollectionsCubit>().createCollection(name);
    setState(() {
      _collectionId = c.id;
      _parentId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollectionsCubit, CollectionsState>(builder: (context, s) {
      final folders = _collectionId == null ? <(NodeRecord, int)>[] : _folders(s);
      return AlertDialog(
        title: Text(context.t(widget.titleKey)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.askName) ...<Widget>[
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(labelText: context.t('common.name')),
                ),
                const SizedBox(height: 14),
              ],
              if (s.collections.isEmpty)
                Text(context.t('save.noCollections'), style: context.secondary)
              else ...<Widget>[
                DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_collectionId),
                  initialValue: _collectionId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.t('save.collection')),
                  items: <DropdownMenuItem<String>>[
                    for (final c in s.collections)
                      DropdownMenuItem<String>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    _collectionId = v;
                    _parentId = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey<String?>('f$_collectionId'),
                  initialValue: _parentId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.t('save.folder')),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(value: null, child: Text(context.t('save.root'))),
                    for (final f in folders)
                      DropdownMenuItem<String?>(
                        value: f.$1.id,
                        child: Text('${'  ' * f.$2}${f.$1.name}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _parentId = v),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _newCollection,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.t('collections.new')),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('common.cancel'))),
          FilledButton(
            onPressed: _collectionId == null
                ? null
                : () => Navigator.pop(
                      context,
                      SaveTarget(
                        collectionId: _collectionId!,
                        parentId: _parentId,
                        name: _name.text.trim(),
                      ),
                    ),
            child: Text(context.t(widget.confirmKey)),
          ),
        ],
      );
    });
  }
}
