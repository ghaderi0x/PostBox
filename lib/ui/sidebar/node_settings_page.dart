import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/collections/domain/node_settings.dart';
import '../../features/requests/domain/request_models.dart';
import '../../l10n/strings.dart';
import '../env/variables_editor.dart' as env;
import '../request/auth_editor.dart';
import '../request/scripts_editor.dart';
import '../widgets/key_value_editor.dart';
import '../widgets/soft.dart';

/// Settings a collection or folder passes down to its requests: auth,
/// headers, variables (folders only) and scripts.
class NodeSettingsPage extends StatefulWidget {
  const NodeSettingsPage({super.key, required this.id});

  /// Id of the collection or folder.
  final String id;

  @override
  State<NodeSettingsPage> createState() => _NodeSettingsPageState();
}

class _NodeSettingsPageState extends State<NodeSettingsPage>
    with SingleTickerProviderStateMixin {
  NodeSettings? _working;
  bool _dirty = false;
  late final TabController _tabs;
  late final bool _isCollection;
  late final String _name;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<CollectionsCubit>();
    final col = cubit.state.collection(widget.id);
    _isCollection = col != null;
    _name = col?.name ?? cubit.state.node(widget.id)?.name ?? '';
    _tabs = TabController(length: _isCollection ? 3 : 4, vsync: this);
    cubit.loadSettings(widget.id).then((s) {
      if (mounted) setState(() => _working = s);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _set(NodeSettings s) => setState(() {
    _working = s;
    _dirty = true;
  });

  Future<void> _save() async {
    final s = _working;
    if (s == null) return;
    final nav = Navigator.of(context);
    await context.read<CollectionsCubit>().saveSettings(widget.id, s);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = _working;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.t(
            _isCollection ? 'nset.titleCollection' : 'nset.titleFolder',
            <String>[_name],
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(context.t('common.save')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                PillTabBar(
                  controller: _tabs,
                  labels: <String>[
                    context.t('req.auth'),
                    context.t('req.headers'),
                    if (!_isCollection) context.t('req.vars'),
                    context.t('req.scripts'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    physics: const NeverScrollableScrollPhysics(),
                    children: <Widget>[
                      AuthEditor(
                        auth: s.auth,
                        inheritLabelKey: 'auth.inheritNode',
                        inheritHint: context.t(
                          _isCollection
                              ? 'nset.authUnsetCollection'
                              : 'nset.authUnsetFolder',
                        ),
                        onChanged: (a) => _set(s.copyWith(auth: a)),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Text(
                              context.t('nset.headersHint'),
                              style: context.secondary,
                            ),
                          ),
                          Expanded(
                            child: KeyValueEditor(
                              items: s.headers,
                              keyHint: 'Header',
                              bulkSeparator: ':',
                              onChanged: (v) => _set(s.copyWith(headers: v)),
                            ),
                          ),
                        ],
                      ),
                      if (!_isCollection)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                              child: Text(
                                context.t('nset.varsHint'),
                                style: context.secondary,
                              ),
                            ),
                            Expanded(
                              child: env.VariablesEditor(
                                variables: s.variables,
                                onChanged: (v) =>
                                    _set(s.copyWith(variables: v)),
                              ),
                            ),
                          ],
                        ),
                      ScriptsEditor(
                        pre: s.preScript,
                        post: s.postScript,
                        onChanged: (pre, post) =>
                            _set(s.copyWith(preScript: pre, postScript: post)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Shown for [AuthType] values in summaries.
String authTypeLabelKey(AuthType t) => 'auth.${t.name}';
