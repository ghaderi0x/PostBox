import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_info.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/environments/application/environments_cubit.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../l10n/strings.dart';
import '../cookies/cookies_page.dart';
import '../env/environments_page.dart';
import '../import_export/import_export_page.dart';
import '../insights/insights_page.dart';
import '../runner/runner_page.dart';
import '../settings/settings_page.dart';
import '../templates/templates_sheet.dart';
import '../workspaces/workspaces_page.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';

/// Phone "Menu" tab: grouped rows in the style of the reference designs.
class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _pickCollection(BuildContext context) async {
    final cols = context.read<CollectionsCubit>().state.collections;
    if (cols.isEmpty) {
      await showToast(context, context.t('menu.noCollections'));
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(ctx.t('menu.pickCollection'), style: ctx.pageTitle),
            ),
            for (final c in cols)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ),
      ),
    );
    if (id != null && context.mounted) {
      _push(context, RunnerPage(collectionId: id));
    }
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();
    final choice = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.t('settings.languageLabel')),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AppLanguage.system),
            child: Text(ctx.t('settings.system')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AppLanguage.en),
            child: const Text('English'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AppLanguage.fa),
            child: const Text('فارسی'),
          ),
        ],
      ),
    );
    if (choice != null) await cubit.update((s) => s.copyWith(language: choice));
  }

  String _languageName(BuildContext context, AppLanguage l) {
    switch (l) {
      case AppLanguage.system:
        return context.t('settings.system');
      case AppLanguage.en:
        return 'English';
      case AppLanguage.fa:
        return 'فارسی';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<SettingsCubit>().state;
    final env = context.watch<EnvironmentsCubit>().state.active;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
          child: Text(
            context.t('menu.title'),
            style: context.pageTitle.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SoftCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              const BrandLogo(size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(appName, style: context.pageTitle),
                    Text(context.t('menu.tagline'), style: context.secondary),
                  ],
                ),
              ),
              Text('v$appVersionLabel', style: context.timingStyle),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GroupedList(
          children: <Widget>[
            GroupedRow(
              icon: Icons.layers_outlined,
              title: context.t('env.title'),
              value: env?.name ?? context.t('env.none'),
              onTap: () => _push(context, const EnvironmentsPage()),
            ),
            GroupedRow(
              icon: Icons.import_export,
              iconColor: c.methodPut,
              title: context.t('ie.title'),
              onTap: () => _push(context, const ImportExportPage()),
            ),
            GroupedRow(
              icon: Icons.play_circle_outline,
              iconColor: c.success,
              title: context.t('menu.runner'),
              onTap: () => _pickCollection(context),
            ),
            GroupedRow(
              icon: Icons.dashboard_customize_outlined,
              title: context.t('palette.fromTemplate'),
              onTap: () => showTemplatePicker(context),
            ),
            GroupedRow(
              icon: Icons.cookie_outlined,
              title: context.t('cookies.title'),
              onTap: () => _push(context, const CookiesPage()),
            ),
            GroupedRow(
              icon: Icons.workspaces_outlined,
              title: context.t('ws.title'),
              onTap: () => _push(context, const WorkspacesPage()),
            ),
            GroupedRow(
              icon: Icons.insights_outlined,
              iconColor: c.accent,
              title: context.t('insights.title'),
              onTap: () => _push(context, const InsightsPage()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GroupedList(
          children: <Widget>[
            GroupedRow(
              icon: Icons.palette_outlined,
              iconColor: c.methodPatch,
              title: context.t('menu.appearance'),
              value: context.t('preset.${settings.themePreset.name}'),
              onTap: () => _push(
                context,
                const SettingsCategoryPage(
                  category: SettingsCategory.appearance,
                ),
              ),
            ),
            GroupedRow(
              icon: Icons.language,
              iconColor: c.methodPut,
              title: context.t('settings.languageLabel'),
              value: _languageName(context, settings.language),
              onTap: () => _pickLanguage(context),
            ),
            GroupedRow(
              icon: Icons.settings_outlined,
              iconColor: c.textSecondary,
              title: context.t('settings.title'),
              onTap: () => _push(context, const SettingsPage()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GroupedList(
          children: <Widget>[
            GroupedRow(
              icon: Icons.explore_outlined,
              iconColor: c.warning,
              title: context.t('menu.tour'),
              onTap: () => context.read<SettingsCubit>().update(
                (s) => s.copyWith(onboardingDone: false),
              ),
            ),
            GroupedRow(
              icon: Icons.privacy_tip_outlined,
              iconColor: c.success,
              title: context.t('about.privacy'),
              onTap: () => showTextDialog(
                context,
                title: context.t('about.privacy'),
                text: context.t('privacy.body'),
              ),
            ),
            GroupedRow(
              icon: Icons.description_outlined,
              iconColor: c.textSecondary,
              title: context.t('about.notices'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: appVersionLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
