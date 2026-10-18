import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../l10n/strings.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(text, style: context.sectionHeading)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 32, color: c.textSecondary),
              const SizedBox(height: 10),
              Text(title, style: context.body.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              if (message != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(message!, style: context.secondary, textAlign: TextAlign.center),
              ],
              if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.detail, this.onRetry});
  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.danger.withAlpha(24),
        border: Border.all(color: c.danger.withAlpha(120)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, color: c.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(message, style: context.errorText),
                if (detail != null && detail!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(detail!, style: context.secondary),
                ],
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(context.t('common.retry'))),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.warning = false});
  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = warning ? c.warning : c.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        border: Border.all(color: color.withAlpha(90)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(warning ? Icons.warning_amber_rounded : Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: context.secondary.copyWith(color: c.textPrimary))),
        ],
      ),
    );
  }
}

class MethodBadge extends StatelessWidget {
  const MethodBadge(this.method, {super.key, this.width = 54});
  final String method;
  final double width;

  @override
  Widget build(BuildContext context) {
    final m = method.toUpperCase();
    final label = m == 'DELETE' ? 'DEL' : (m == 'OPTIONS' ? 'OPT' : (m == 'PATCH' ? 'PATCH' : m));
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: context.methodBadge.copyWith(color: context.colors.methodColor(m)),
        textDirection: TextDirection.ltr,
        overflow: TextOverflow.clip,
        maxLines: 1,
      ),
    );
  }
}

Future<void> showToast(BuildContext context, String message) async {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

Future<void> copyText(BuildContext context, String text, {String? toast}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) await showToast(context, toast ?? context.t('common.copied'));
}

/// Confirms a destructive action. Skipped when the user turned confirmations
/// off in Settings. Pass [force] for irreversible bulk deletes.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool force = false,
}) async {
  if (!force && !context.read<SettingsCubit>().state.confirmDestructive) return true;
  final c = context.colors;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('common.cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Theme.of(ctx).colorScheme.onError),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? ctx.t('common.delete')),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? label,
  String? confirmLabel,
  int maxLines = 1,
}) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('common.cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: Text(confirmLabel ?? ctx.t('common.ok')),
        ),
      ],
    ),
  );
  ctl.dispose();
  return r;
}

/// Shows [text] in a dialog with copy; used for exports and logs.
Future<void> showTextDialog(
  BuildContext context, {
  required String title,
  required String text,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        height: 360,
        child: SingleChildScrollView(
          child: SelectableText(text, style: ctx.mono.copyWith(fontSize: 12)),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => copyText(ctx, text), child: Text(ctx.t('common.copy'))),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('common.close'))),
      ],
    ),
  );
}
