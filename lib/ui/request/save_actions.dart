import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/collections/application/collections_cubit.dart';
import '../../features/requests/domain/request_models.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../sidebar/save_dialog.dart';
import '../widgets/common.dart';

/// Saves [tab]. Unsaved requests and "save as" ask for a collection first.
Future<void> saveTab(BuildContext context, RequestTab tab, {bool saveAs = false}) async {
  final ws = context.read<WorkspaceCubit>();
  final collections = context.read<CollectionsCubit>();
  if (tab.isSaved && !saveAs) {
    await ws.save(tab.id);
    if (context.mounted) await showToast(context, context.t('save.saved'));
    return;
  }
  final target = await showSaveRequestDialog(
    context,
    initialName: tab.draft.displayName,
    preferredCollectionId: tab.collectionId,
  );
  if (target == null || !context.mounted) return;
  var r = tab.draft;
  if (target.name.isNotEmpty) r = r.copyWith(name: target.name);
  if (saveAs && tab.isSaved) {
    // A copy under a new id; the original stays as it was.
    r = r.copyWith(id: RequestModel.blank().id);
    final node = await collections.saveRequest(
      request: r,
      collectionId: target.collectionId,
      parentId: target.parentId,
    );
    await ws.openNode(node);
  } else {
    ws.update(tab.id, r);
    await ws.save(tab.id, collectionId: target.collectionId, parentId: target.parentId);
  }
  if (context.mounted) await showToast(context, context.t('save.saved'));
}
