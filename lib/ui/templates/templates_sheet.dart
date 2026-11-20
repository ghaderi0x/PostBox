import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/typography.dart';
import '../../features/requests/domain/request_models.dart';
import '../../features/templates/request_templates.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

/// Lets the user start a new request from a built-in or saved template.
Future<void> showTemplatePicker(BuildContext context) {
  final store = context.read<TemplateStore>();
  final ws = context.read<WorkspaceCubit>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _TemplateList(
      store: store,
      onPick: (t) {
        ws.newTab(model: t.instantiate());
        Navigator.of(ctx).pop();
      },
    ),
  );
}

/// Saves [request] as a user template after asking for a name. Secrets are
/// never stored in templates.
Future<void> saveAsTemplate(BuildContext context, RequestModel request) async {
  final store = context.read<TemplateStore>();
  final name = await promptText(
    context,
    title: context.t('tpl.saveAs'),
    initial: request.displayName,
    label: context.t('common.name'),
  );
  if (name == null || name.trim().isEmpty) return;
  store.add(name.trim(), request);
  if (context.mounted) await showToast(context, context.t('tpl.saved'));
}

class _TemplateList extends StatefulWidget {
  const _TemplateList({required this.store, required this.onPick});
  final TemplateStore store;
  final void Function(RequestTemplate) onPick;

  @override
  State<_TemplateList> createState() => _TemplateListState();
}

class _TemplateListState extends State<_TemplateList> {
  @override
  Widget build(BuildContext context) {
    final user = widget.store.list();
    final all = <RequestTemplate>[...user, ...builtInTemplates()];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(context.t('tpl.title'), style: context.pageTitle),
            ),
            for (final t in all)
              ListTile(
                leading: SizedBox(
                  width: 56,
                  child: MethodBadge(t.request.method),
                ),
                title: Text(t.name),
                subtitle: Text(
                  t.builtIn ? context.t('tpl.builtIn') : t.request.url,
                  style: context.secondary,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onPick(t),
                trailing: t.builtIn
                    ? null
                    : IconButton(
                        tooltip: context.t('common.delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          widget.store.delete(t.id);
                          setState(() {});
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
