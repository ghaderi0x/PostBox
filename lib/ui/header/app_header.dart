import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_info.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../features/shortcuts/shortcut_catalog.dart';
import '../../features/workspaces/workspace_registry.dart';
import '../../l10n/strings.dart';
import '../widgets/brand.dart';
import '../widgets/env_selector.dart';
import '../widgets/pressable.dart';

/// Top bar of the desktop layout.
///
/// Left: logo, name and the active workspace. Centre: a search field that
/// opens the command palette and shows its shortcut. Right: environment
/// picker, then icon buttons for import/export, the theme and settings.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.onPalette,
    required this.onImportExport,
    required this.onSettings,
    required this.onWorkspaces,
  });

  static const double height = 56;

  final VoidCallback onPalette;
  final VoidCallback onImportExport;
  final VoidCallback onSettings;
  final VoidCallback onWorkspaces;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shortcut = effectiveShortcuts(
      context.select((SettingsCubit s) => s.state.shortcuts),
    )[ShortcutAction.commandPalette]!.display();
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surfaceBase,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: <Widget>[
          const BrandMark(name: appName),
          const SizedBox(width: 12),
          _WorkspaceChip(onTap: onWorkspaces),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _SearchField(shortcut: shortcut, onTap: onPalette),
              ),
            ),
          ),
          const EnvSelector(),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: c.border),
          const SizedBox(width: 8),
          HeaderIconButton(
            tooltip: context.t('ie.title'),
            icon: Icons.import_export,
            onPressed: onImportExport,
          ),
          const _ThemeButton(),
          HeaderIconButton(
            tooltip: context.t('settings.title'),
            icon: Icons.settings_outlined,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

/// Square icon button with a hover background; the same size everywhere in
/// the header so the row looks even.
class HeaderIconButton extends StatefulWidget {
  const HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  State<HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<HeaderIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: Pressable(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onPressed,
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: _hover || widget.active
                    ? c.border.withAlpha(widget.active ? 110 : 70)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: widget.active ? c.accent : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.shortcut, required this.onTap});

  final String shortcut;
  final VoidCallback onTap;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: context.t('palette.title'),
        child: Pressable(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hover ? c.accent.withAlpha(140) : c.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.search, size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t('header.search'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    widget.shortcut,
                    textDirection: TextDirection.ltr,
                    style: context.mono.copyWith(
                      fontSize: 11,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceChip extends StatelessWidget {
  const _WorkspaceChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = context.read<WorkspaceManager>().registry.active;
    final name = active.id == kDefaultWorkspaceId && active.name == 'Default'
        ? context.t('ws.default')
        : active.name;
    return Tooltip(
      message: context.t('header.workspace', <String>[name]),
      child: Pressable(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: c.accent.withAlpha(28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.workspaces_outlined, size: 14, color: c.accent),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.secondary.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switches between the dark and light theme. "System" is still available in
/// Settings > Appearance.
class _ThemeButton extends StatelessWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return HeaderIconButton(
      tooltip: context.t('header.toggleTheme'),
      icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      onPressed: () => context.read<SettingsCubit>().update(
        (s) => s.copyWith(
          themeMode: dark ? AppThemeMode.light : AppThemeMode.dark,
        ),
      ),
    );
  }
}
