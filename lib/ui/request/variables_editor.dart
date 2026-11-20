import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/model/key_value.dart';
import '../../features/environments/domain/variables.dart';
import '../../features/requests/domain/request_models.dart';
import '../../l10n/strings.dart';
import '../widgets/key_value_editor.dart';

/// Request-level variables plus the resolution inspector: every `{{name}}`
/// used by the request with the value it resolves to and which layer
/// (global, collection, folder, request, environment, runtime) it came from.
class VariablesEditor extends StatelessWidget {
  const VariablesEditor({
    super.key,
    required this.request,
    required this.resolver,
    required this.onChanged,
  });

  final RequestModel request;
  final VariableResolver resolver;
  final ValueChanged<List<KeyValue>> onChanged;

  /// Names of all variables the request refers to, in first-use order.
  static List<String> usedNames(RequestModel r) {
    final texts = <String>[
      r.url,
      r.body,
      r.bodyAux,
      for (final k in <KeyValue>[...r.headers, ...r.params, ...r.formFields])
        '${k.key} ${k.value}',
      r.auth.token,
      r.auth.username,
      r.auth.password,
      r.auth.apiKeyName,
      r.auth.apiKeyValue,
    ];
    final seen = <String>{};
    final out = <String>[];
    for (final t in texts) {
      for (final m in kVariablePattern.allMatches(t)) {
        if (seen.add(m[1]!)) out.add(m[1]!);
      }
    }
    return out;
  }

  static String sourceKey(VariableSource s) => 'var.source.${s.name}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final used = usedNames(request);
    return Column(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Text(
                  context.t('var.requestHint'),
                  style: context.secondary,
                ),
              ),
              Expanded(
                child: KeyValueEditor(
                  items: request.variables,
                  bulkSeparator: '=',
                  keyHint: context.t('var.name'),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              Text(context.t('var.inspector'), style: context.sectionHeading),
              const SizedBox(height: 4),
              Text(context.t('var.inspectorHint'), style: context.secondary),
              const SizedBox(height: 8),
              if (used.isEmpty)
                Text(context.t('var.noneUsed'), style: context.secondary)
              else
                for (final name in used) _Row(name: name, resolver: resolver),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.resolver});
  final String name;
  final VariableResolver resolver;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final source = resolver.sourceOf(name);
    final value = resolver.displayValue(name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            source == null ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: source == null ? c.warning : c.success,
          ),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('{{$name}}', style: context.mono)),
          Expanded(
            flex: 3,
            child: Text(
              source == null
                  ? context.t('var.undefined')
                  : (value!.isEmpty ? context.t('var.empty') : value),
              style: context.mono.copyWith(
                color: source == null ? c.warning : c.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (source != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(
                context.t(VariablesEditor.sourceKey(source)),
                style: context.secondary,
              ),
            ),
        ],
      ),
    );
  }
}
