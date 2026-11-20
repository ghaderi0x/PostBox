import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/environments/application/environments_cubit.dart';
import '../../l10n/strings.dart';
import '../env/environments_page.dart';

/// Active environment picker with a shortcut to the manager.
class EnvSelector extends StatelessWidget {
  const EnvSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<EnvironmentsCubit, EnvironmentsState>(
      builder: (context, s) {
        final active = s.active;
        return PopupMenuButton<String>(
          tooltip: context.t('env.title'),
          onSelected: (v) {
            if (v == '*manage') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EnvironmentsPage(),
                ),
              );
            } else if (v == '*none') {
              context.read<EnvironmentsCubit>().setActive(null);
            } else {
              context.read<EnvironmentsCubit>().setActive(v);
            }
          },
          itemBuilder: (ctx) => <PopupMenuEntry<String>>[
            CheckedPopupMenuItem<String>(
              value: '*none',
              checked: active == null,
              child: Text(ctx.t('env.none')),
            ),
            for (final e in s.environments)
              CheckedPopupMenuItem<String>(
                value: e.id,
                checked: e.id == s.activeId,
                child: Text(e.name),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: '*manage',
              child: Text(ctx.t('env.manage')),
            ),
          ],
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.layers_outlined,
                  size: 16,
                  color: active == null ? c.textSecondary : c.accent,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    active?.name ?? context.t('env.none'),
                    overflow: TextOverflow.ellipsis,
                    style: context.body,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 18, color: c.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }
}
