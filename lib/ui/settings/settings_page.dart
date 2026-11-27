import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/design/presets.dart';
import '../../core/design/shapes.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/file_service.dart';
import '../../core/platform/platform_info.dart';
import '../../core/util/app_log.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/data/app_data_service.dart';
import '../../features/environments/application/environments_cubit.dart';
import '../../features/history/application/history_cubit.dart';
import '../../features/http/domain/http_engine.dart';
import '../../features/secrets/secret_store.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../features/shortcuts/shortcut_catalog.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../cookies/cookies_page.dart';
import '../shortcuts/shortcuts_page.dart';
import '../update/update_prompt.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/key_value_editor.dart';
import '../widgets/soft.dart';
import '../workspaces/workspaces_page.dart';
import '../widgets/pressable.dart';

/// The groups of settings. Each one is its own page (phones) or its own pane
/// (wide windows) so no single screen holds every setting.
enum SettingsCategory {
  appearance(Icons.palette_outlined, 'settings.appearance'),
  language(Icons.language, 'settings.language'),
  requests(Icons.swap_horiz, 'settings.requests'),
  editor(Icons.code, 'settings.editor'),
  privacy(Icons.privacy_tip_outlined, 'settings.privacy'),
  keyboard(Icons.keyboard_outlined, 'settings.keyboard'),
  developer(Icons.bug_report_outlined, 'settings.diagnostics'),
  about(Icons.info_outline, 'settings.about');

  const SettingsCategory(this.icon, this.titleKey);

  final IconData icon;
  final String titleKey;

  String get descriptionKey => 'settings.cat.$name';

  /// Groups shown on this device. The keyboard shortcut guide is for
  /// Windows and Linux only, so phones do not list it.
  static List<SettingsCategory> get available => <SettingsCategory>[
    for (final c in values)
      if (c != keyboard || isDesktopPlatform) c,
  ];
}

Widget _categoryBody(SettingsCategory category, AppSettings s) {
  switch (category) {
    case SettingsCategory.appearance:
      return _Appearance(s: s);
    case SettingsCategory.language:
      return _Language(s: s);
    case SettingsCategory.requests:
      return _Requests(s: s);
    case SettingsCategory.editor:
      return _EditorSection(s: s);
    case SettingsCategory.privacy:
      return _Privacy(s: s);
    case SettingsCategory.keyboard:
      return const _Keyboard();
    case SettingsCategory.developer:
      return const _Diagnostics();
    case SettingsCategory.about:
      return const _About();
  }
}

/// Settings home. On wide windows: a list of groups on the left and the
/// selected group on the right. On narrow windows: a list of groups that open
/// one page each.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initial});

  /// Group to show first. On narrow windows it opens straight away.
  final SettingsCategory? initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsCategory _selected =
      SettingsCategory.available.contains(widget.initial)
      ? widget.initial!
      : SettingsCategory.appearance;
  final ScrollController _paneScroll = ScrollController();
  bool _openedInitial = false;

  /// Desktop windows switch to the two-pane layout earlier than phones and
  /// tablets, so a small desktop window never shows the phone-style list.
  static double get _wide => isDesktopPlatform ? 700 : 860;

  @override
  void dispose() {
    _paneScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Narrow layout: jump to the requested group once.
    if (!_openedInitial && widget.initial != null) {
      _openedInitial = true;
      if (MediaQuery.of(context).size.width < _wide) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openCategory(widget.initial!);
        });
      }
    }
  }

  void _openCategory(SettingsCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsCategoryPage(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.title'))),
      body: LayoutBuilder(
        builder: (context, cons) {
          final wide = cons.maxWidth >= _wide;
          return wide ? _twoPane(context) : _hub(context);
        },
      ),
    );
  }

  Widget _hub(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        for (final cat in SettingsCategory.available)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(Radii.lg),
              child: Pressable(
                borderRadius: BorderRadius.circular(Radii.lg),
                onTap: () => _openCategory(cat),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Row(
                    children: <Widget>[
                      IconTile(icon: cat.icon, color: c.accent, size: 42),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.t(cat.titleKey),
                              style: context.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.t(cat.descriptionKey),
                              style: context.secondary,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _move(int delta) {
    final cats = SettingsCategory.available;
    final i = cats.indexOf(_selected);
    final next = (i + delta).clamp(0, cats.length - 1);
    if (next != i) setState(() => _selected = cats[next]);
  }

  Widget _twoPane(BuildContext context) {
    final c = context.colors;
    final reduced = context.pb.reducedMotion;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Row(
          children: <Widget>[
            Container(
              width: 256,
              decoration: BoxDecoration(
                color: c.surfaceBase,
                border: BorderDirectional(end: BorderSide(color: c.border)),
              ),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Row(
                      children: <Widget>[
                        const BrandLogo(size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(appName, style: context.pageTitle),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                      children: <Widget>[
                        for (final cat in SettingsCategory.available)
                          _NavItem(
                            category: cat,
                            selected: cat == _selected,
                            onTap: () => setState(() => _selected = cat),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                    child: Row(
                      children: <Widget>[
                        Text('v$appVersionLabel', style: context.timingStyle),
                        const Spacer(),
                        Icon(
                          Icons.unfold_more,
                          size: 14,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.t('settings.navHint'),
                          style: context.secondary.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<SettingsCubit, AppSettings>(
                builder: (context, s) => Scrollbar(
                  controller: _paneScroll,
                  thumbVisibility: true,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: ListView(
                        controller: _paneScroll,
                        padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                        children: <Widget>[
                          AnimatedSwitcher(
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            child: Column(
                              key: ValueKey<SettingsCategory>(_selected),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _CategoryHeader(category: _selected),
                                _categoryBody(_selected, s),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of the settings sidebar on desktop: icon, title, accent marker.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Pressable(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? c.accent.withAlpha(30) : null,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 9),
                decoration: BoxDecoration(
                  color: selected ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                category.icon,
                size: 19,
                color: selected ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t(category.titleKey),
                  overflow: TextOverflow.ellipsis,
                  style: context.body.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? c.accent : c.textPrimary,
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

/// One group of settings as its own page (used on narrow windows).
class SettingsCategoryPage extends StatelessWidget {
  const SettingsCategoryPage({super.key, required this.category});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t(category.titleKey))),
      body: BlocBuilder<SettingsCubit, AppSettings>(
        builder: (context, s) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: <Widget>[_categoryBody(category, s)],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.t(category.titleKey),
          style: context.pageTitle.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 4),
        Text(context.t(category.descriptionKey), style: context.secondary),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Semantics(
        label: title,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: softShadow(context, strength: 0.6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              // ListTiles and switches paint on the nearest Material, so give
              // them one inside this coloured card.
              child: Material(
                type: MaterialType.transparency,
                child: Column(children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.help});
  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: context.formLabel),
        const SizedBox(height: 6),
        child,
        if (help != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(help!, style: context.secondary),
        ],
      ],
    ),
  );
}

Widget _switch(
  BuildContext context,
  String label,
  bool value,
  ValueChanged<bool> onChanged, {
  String? help,
}) {
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label, style: context.body),
    subtitle: help == null ? null : Text(help, style: context.secondary),
    value: value,
    onChanged: onChanged,
  );
}

Widget _segmented<T>(
  T value,
  Map<T, String> options,
  ValueChanged<T> onChanged,
) {
  return SegmentedButton<T>(
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    showSelectedIcon: false,
    segments: <ButtonSegment<T>>[
      for (final e in options.entries)
        ButtonSegment<T>(value: e.key, label: Text(e.value)),
    ],
    selected: <T>{value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}

class _IntField extends StatefulWidget {
  const _IntField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix,
  });
  final int value;
  final int min;
  final int max;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _c = TextEditingController(
    text: '${widget.value}',
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: _c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          suffixText: widget.suffix,
          errorText: _error,
        ),
        onChanged: (v) {
          final n = int.tryParse(v.trim());
          if (n == null || n < widget.min || n > widget.max) {
            setState(() => _error = '${widget.min}-${widget.max}');
          } else {
            setState(() => _error = null);
            widget.onChanged(n);
          }
        },
      ),
    );
  }
}

// --- Appearance ---------------------------------------------------------

class _Appearance extends StatelessWidget {
  const _Appearance({required this.s});
  final AppSettings s;

  Future<void> _customAccent(BuildContext context) async {
    final hex = await promptText(
      context,
      title: context.t('settings.customAccent'),
      label: 'RRGGBB',
      initial: '',
    );
    if (hex == null || !context.mounted) return;
    final clean = hex.trim().replaceFirst('#', '');
    final v = int.tryParse(clean, radix: 16);
    if (clean.length != 6 || v == null) {
      await showToast(context, context.t('settings.badHex'));
      return;
    }
    await context.read<SettingsCubit>().update(
      (x) => x.copyWith(accentOverride: 0xFF000000 | v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    final c = context.colors;
    return _Section(
      title: context.t('settings.appearance'),
      children: <Widget>[
        _Field(
          label: context.t('settings.themeMode'),
          child: _segmented<AppThemeMode>(s.themeMode, <AppThemeMode, String>{
            AppThemeMode.system: context.t('settings.system'),
            AppThemeMode.light: context.t('settings.light'),
            AppThemeMode.dark: context.t('settings.dark'),
          }, (v) => cubit.update((x) => x.copyWith(themeMode: v))),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('settings.schedule')),
          subtitle: Text(context.t('settings.scheduleHelp')),
          value: s.themeSchedule,
          onChanged: (v) => cubit.update((x) => x.copyWith(themeSchedule: v)),
        ),
        if (s.themeSchedule)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _TimeField(
                    label: context.t('settings.darkFrom'),
                    minutes: s.darkFromMinutes,
                    onPicked: (m) =>
                        cubit.update((x) => x.copyWith(darkFromMinutes: m)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeField(
                    label: context.t('settings.darkTo'),
                    minutes: s.darkToMinutes,
                    onPicked: (m) =>
                        cubit.update((x) => x.copyWith(darkToMinutes: m)),
                  ),
                ),
              ],
            ),
          ),
        _Field(
          label: context.t('settings.preset'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final p in ThemePreset.values)
                ChoiceChip(
                  avatar: CircleAvatar(
                    radius: 7,
                    backgroundColor: buildColors(
                      p,
                      Theme.of(context).brightness,
                    ).accent,
                  ),
                  label: Text(context.t('preset.${p.name}')),
                  selected: s.themePreset == p,
                  onSelected: (_) =>
                      cubit.update((x) => x.copyWith(themePreset: p)),
                ),
            ],
          ),
        ),
        _Field(
          label: context.t('settings.accent'),
          help: context.t('settings.accentHelp'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ChoiceChip(
                label: Text(context.t('settings.presetAccent')),
                selected: s.accentOverride == null,
                onSelected: (_) =>
                    cubit.update((x) => x.copyWith(clearAccent: true)),
              ),
              for (final a in kAccentSwatches)
                Pressable(
                  circle: true,
                  onTap: () =>
                      cubit.update((x) => x.copyWith(accentOverride: a)),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(a),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.accentOverride == a ? c.textPrimary : c.border,
                        width: s.accentOverride == a ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: () => _customAccent(context),
                child: Text(context.t('settings.custom')),
              ),
            ],
          ),
        ),
        _Field(
          label: context.t('settings.surface'),
          child:
              _segmented<SurfaceStyle>(s.surfaceStyle, <SurfaceStyle, String>{
                SurfaceStyle.raised: context.t('settings.raised'),
                SurfaceStyle.flat: context.t('settings.flat'),
              }, (v) => cubit.update((x) => x.copyWith(surfaceStyle: v))),
        ),
        _Field(
          label: context.t('settings.density'),
          child: _segmented<UiDensity>(s.density, <UiDensity, String>{
            UiDensity.comfortable: context.t('settings.comfortable'),
            UiDensity.compact: context.t('settings.compact'),
          }, (v) => cubit.update((x) => x.copyWith(density: v))),
        ),
      ],
    );
  }
}

// --- Language and accessibility ------------------------------------------

class _Language extends StatelessWidget {
  const _Language({required this.s});
  final AppSettings s;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Section(
      title: context.t('settings.language'),
      children: <Widget>[
        _Field(
          label: context.t('settings.languageLabel'),
          child: _segmented<AppLanguage>(s.language, <AppLanguage, String>{
            AppLanguage.system: context.t('settings.system'),
            AppLanguage.en: 'English',
            AppLanguage.fa: 'فارسی',
          }, (v) => cubit.update((x) => x.copyWith(language: v))),
        ),
        _switch(
          context,
          context.t('settings.persianDigits'),
          s.persianDigits,
          (v) => cubit.update((x) => x.copyWith(persianDigits: v)),
          help: context.t('settings.persianDigitsHelp'),
        ),
        _switch(
          context,
          context.t('settings.jalali'),
          s.jalaliDates,
          (v) => cubit.update((x) => x.copyWith(jalaliDates: v)),
          help: context.t('settings.jalaliHelp'),
        ),
        _Field(
          label:
              '${context.t('settings.fontScale')}: ${(s.fontScale * 100).round()}%',
          child: Slider(
            value: s.fontScale,
            min: 0.8,
            max: 1.6,
            divisions: 16,
            onChanged: (v) => cubit.update(
              (x) => x.copyWith(fontScale: double.parse(v.toStringAsFixed(2))),
            ),
          ),
        ),
        _switch(
          context,
          context.t('settings.reducedMotion'),
          s.reducedMotion,
          (v) => cubit.update((x) => x.copyWith(reducedMotion: v)),
          help: context.t('settings.reducedMotionHelp'),
        ),
      ],
    );
  }
}

// --- Requests -------------------------------------------------------------

class _Requests extends StatefulWidget {
  const _Requests({required this.s});
  final AppSettings s;

  @override
  State<_Requests> createState() => _RequestsState();
}

class _RequestsState extends State<_Requests> {
  late final TextEditingController _proxy = TextEditingController(
    text: widget.s.proxy,
  );
  String? _proxyError;

  @override
  void dispose() {
    _proxy.dispose();
    super.dispose();
  }

  Future<void> _toggleTls(bool allow) async {
    final cubit = context.read<SettingsCubit>();
    if (allow) {
      final ok = await confirmDestructive(
        context,
        title: context.t('settings.tlsOffTitle'),
        message: context.t('settings.tlsOffMsg'),
        confirmLabel: context.t('settings.tlsOffConfirm'),
        force: true,
      );
      if (!ok) return;
    }
    await cubit.update((x) => x.copyWith(allowInvalidCertificates: allow));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cubit = context.read<SettingsCubit>();
    final c = context.colors;
    return _Section(
      title: context.t('settings.requests'),
      children: <Widget>[
        _Field(
          label: context.t('settings.defaultMethod'),
          child: DropdownButton<String>(
            value: kHttpMethods.contains(s.defaultMethod)
                ? s.defaultMethod
                : null,
            hint: Text(s.defaultMethod),
            items: <DropdownMenuItem<String>>[
              for (final m in kHttpMethods)
                DropdownMenuItem<String>(value: m, child: Text(m)),
            ],
            onChanged: (v) {
              if (v != null) cubit.update((x) => x.copyWith(defaultMethod: v));
            },
          ),
        ),
        _Field(
          label: context.t('settings.timeout'),
          child: _IntField(
            value: s.timeoutSeconds,
            min: 1,
            max: 600,
            suffix: 's',
            onChanged: (v) =>
                cubit.update((x) => x.copyWith(timeoutSeconds: v)),
          ),
        ),
        _Field(
          label: context.t('settings.redirects'),
          help: context.t('settings.redirectsHelp'),
          child: DropdownButton<RedirectPolicy>(
            value: s.redirectPolicy,
            items: <DropdownMenuItem<RedirectPolicy>>[
              for (final p in RedirectPolicy.values)
                DropdownMenuItem<RedirectPolicy>(
                  value: p,
                  child: Text(context.t('redirect.${p.name}')),
                ),
            ],
            onChanged: (v) {
              if (v != null) cubit.update((x) => x.copyWith(redirectPolicy: v));
            },
          ),
        ),
        _Field(
          label: context.t('settings.maxRedirects'),
          child: _IntField(
            value: s.maxRedirects,
            min: 0,
            max: 30,
            onChanged: (v) => cubit.update((x) => x.copyWith(maxRedirects: v)),
          ),
        ),
        _Field(
          label: context.t('settings.proxy'),
          help: context.t('settings.proxyHelp'),
          child: SizedBox(
            width: 280,
            child: TextField(
              controller: _proxy,
              style: context.mono,
              decoration: InputDecoration(
                hintText: '127.0.0.1:8080',
                errorText: _proxyError,
              ),
              onChanged: (v) {
                final t = v.trim();
                if (isValidProxy(t)) {
                  setState(() => _proxyError = null);
                  cubit.update((x) => x.copyWith(proxy: t));
                } else {
                  setState(
                    () => _proxyError = context.t('settings.proxyInvalid'),
                  );
                }
              },
            ),
          ),
        ),
        _switch(
          context,
          context.t('settings.allowInvalidTls'),
          s.allowInvalidCertificates,
          _toggleTls,
          help: context.t('settings.allowInvalidTlsHelp'),
        ),
        if (s.allowInvalidCertificates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InfoBanner(context.t('settings.tlsWarning'), warning: true),
          ),
        _Field(
          label: context.t('settings.httpVersion'),
          help: context.t('settings.httpVersionHelp'),
          child: _segmented<HttpVersionPref>(
            s.httpVersion,
            <HttpVersionPref, String>{
              HttpVersionPref.http1: 'HTTP/1.1',
              HttpVersionPref.auto: context.t('settings.httpAuto'),
            },
            (v) => cubit.update((x) => x.copyWith(httpVersion: v)),
          ),
        ),
        _switch(
          context,
          context.t('cookies.useJar'),
          s.useCookieJar,
          (v) => cubit.update((x) => x.copyWith(useCookieJar: v)),
          help: context.t('cookies.useJarHint'),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.cookie_outlined, size: 16),
            label: Text(context.t('settings.manageCookies')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CookiesPage()),
            ),
          ),
        ),
        _CertFields(s: s),
        _Field(
          label: context.t('settings.maxResponse'),
          child: _IntField(
            value: s.maxResponseMb,
            min: 1,
            max: 200,
            suffix: 'MB',
            onChanged: (v) => cubit.update((x) => x.copyWith(maxResponseMb: v)),
          ),
        ),
        _Field(
          label: context.t('settings.maxRequest'),
          child: _IntField(
            value: s.maxRequestMb,
            min: 1,
            max: 100,
            suffix: 'MB',
            onChanged: (v) => cubit.update((x) => x.copyWith(maxRequestMb: v)),
          ),
        ),
        _Field(
          label: context.t('settings.defaultHeaders'),
          help: context.t('settings.defaultHeadersHelp'),
          child: Container(
            height: (s.defaultHeaders.length + 1) * 52.0 + 24,
            constraints: const BoxConstraints(minHeight: 90),
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: KeyValueEditor(
              items: s.defaultHeaders,
              keyHint: 'Header',
              onChanged: (v) =>
                  cubit.update((x) => x.copyWith(defaultHeaders: v)),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Editor -----------------------------------------------------------------

class _EditorSection extends StatelessWidget {
  const _EditorSection({required this.s});
  final AppSettings s;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Section(
      title: context.t('settings.editor'),
      children: <Widget>[
        _switch(
          context,
          context.t('settings.wordWrap'),
          s.editorWordWrap,
          (v) => cubit.update((x) => x.copyWith(editorWordWrap: v)),
        ),
        _switch(
          context,
          context.t('settings.lineNumbers'),
          s.editorLineNumbers,
          (v) => cubit.update((x) => x.copyWith(editorLineNumbers: v)),
        ),
        _switch(
          context,
          context.t('settings.autoClose'),
          s.editorAutoClose,
          (v) => cubit.update((x) => x.copyWith(editorAutoClose: v)),
        ),
        _switch(
          context,
          context.t('settings.highlightVars'),
          s.editorHighlightVariables,
          (v) => cubit.update((x) => x.copyWith(editorHighlightVariables: v)),
        ),
        _Field(
          label:
              '${context.t('settings.editorFontSize')}: ${s.editorFontSize.round()}',
          child: Slider(
            value: s.editorFontSize,
            min: 10,
            max: 24,
            divisions: 14,
            onChanged: (v) => cubit.update(
              (x) => x.copyWith(editorFontSize: v.roundToDouble()),
            ),
          ),
        ),
        _Field(
          label: context.t('settings.tabSize'),
          child: _segmented<int>(s.editorTabSize, const <int, String>{
            2: '2',
            4: '4',
          }, (v) => cubit.update((x) => x.copyWith(editorTabSize: v))),
        ),
      ],
    );
  }
}

// --- Data and privacy ---------------------------------------------------------

class _Privacy extends StatelessWidget {
  const _Privacy({required this.s});
  final AppSettings s;

  Future<void> _clearHistory(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('history.clearTitle'),
      message: context.t('history.clearMsg'),
      confirmLabel: context.t('history.clear'),
      force: true,
    );
    if (ok && context.mounted) {
      context.read<HistoryCubit>().clear();
      await showToast(context, context.t('settings.historyCleared'));
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('settings.clearAllTitle'),
      message: context.t('settings.clearAllMsg'),
      confirmLabel: context.t('settings.clearAllConfirm'),
      force: true,
    );
    if (!ok || !context.mounted) return;
    final data = context.read<AppDataService>();
    final collections = context.read<CollectionsCubit>();
    final envs = context.read<EnvironmentsCubit>();
    final history = context.read<HistoryCubit>();
    final ws = context.read<WorkspaceCubit>();
    await data.clearAll();
    await collections.load();
    await envs.load();
    history.refresh();
    await ws.reset();
    if (context.mounted) {
      await showToast(context, context.t('settings.clearedAll'));
    }
  }

  Future<void> _export(BuildContext context) async {
    final text = context.read<SettingsCubit>().exportJson();
    await showTextDialog(
      context,
      title: context.t('settings.exportSettings'),
      text: text,
    );
  }

  Future<void> _import(BuildContext context) async {
    final text = await promptText(
      context,
      title: context.t('settings.importSettings'),
      label: context.t('settings.pasteJson'),
      maxLines: 8,
      confirmLabel: context.t('settings.import'),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    final err = await context.read<SettingsCubit>().importJson(text);
    if (!context.mounted) return;
    await showToast(
      context,
      err == null
          ? context.t('settings.imported')
          : context.t('settings.importFailed.$err'),
    );
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('settings.resetTitle'),
      message: context.t('settings.resetMsg'),
      confirmLabel: context.t('settings.reset'),
      force: true,
    );
    if (ok && context.mounted) {
      await context.read<SettingsCubit>().resetToDefaults();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Section(
      title: context.t('settings.privacy'),
      children: <Widget>[
        _switch(
          context,
          context.t('settings.restore'),
          s.restoreWorkspace,
          (v) => context.read<SettingsCubit>().update(
            (x) => x.copyWith(restoreWorkspace: v),
          ),
          help: context.t('settings.restoreHint'),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.workspaces_outlined, size: 16),
            label: Text(context.t('ws.title')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WorkspacesPage()),
            ),
          ),
        ),
        _switch(
          context,
          context.t('settings.persistHistory'),
          s.persistHistory,
          (v) => cubit.update((x) => x.copyWith(persistHistory: v)),
        ),
        _switch(
          context,
          context.t('settings.omitSensitive'),
          s.omitSensitiveInHistory,
          (v) => cubit.update((x) => x.copyWith(omitSensitiveInHistory: v)),
          help: context.t('settings.omitSensitiveHelp'),
        ),
        _Field(
          label: context.t('settings.retention'),
          child: DropdownButton<int>(
            value:
                const <int>[0, 7, 30, 90, 365].contains(s.historyRetentionDays)
                ? s.historyRetentionDays
                : null,
            hint: Text('${s.historyRetentionDays}'),
            items: <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(
                value: 7,
                child: Text(context.t('settings.days', <String>['7'])),
              ),
              DropdownMenuItem<int>(
                value: 30,
                child: Text(context.t('settings.days', <String>['30'])),
              ),
              DropdownMenuItem<int>(
                value: 90,
                child: Text(context.t('settings.days', <String>['90'])),
              ),
              DropdownMenuItem<int>(
                value: 365,
                child: Text(context.t('settings.days', <String>['365'])),
              ),
              DropdownMenuItem<int>(
                value: 0,
                child: Text(context.t('settings.forever')),
              ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await cubit.update((x) => x.copyWith(historyRetentionDays: v));
              if (context.mounted) {
                context.read<HistoryCubit>().prune(cubit.state);
              }
            },
          ),
        ),
        _Field(
          label: context.t('settings.maxHistory'),
          child: _IntField(
            value: s.historyMaxEntries,
            min: 10,
            max: 10000,
            onChanged: (v) async {
              await cubit.update((x) => x.copyWith(historyMaxEntries: v));
              if (context.mounted) {
                context.read<HistoryCubit>().prune(cubit.state);
              }
            },
          ),
        ),
        _switch(
          context,
          context.t('settings.confirmDestructive'),
          s.confirmDestructive,
          (v) => cubit.update((x) => x.copyWith(confirmDestructive: v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: InfoBanner(context.t('settings.noTelemetry')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => _clearHistory(context),
                child: Text(context.t('history.clear')),
              ),
              OutlinedButton(
                onPressed: () => _export(context),
                child: Text(context.t('settings.exportSettings')),
              ),
              OutlinedButton(
                onPressed: () => _import(context),
                child: Text(context.t('settings.importSettings')),
              ),
              OutlinedButton(
                onPressed: () => _reset(context),
                child: Text(context.t('settings.reset')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => _clearAll(context),
                child: Text(context.t('settings.clearAll')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Keyboard ---------------------------------------------------------------

class _Keyboard extends StatelessWidget {
  const _Keyboard();

  @override
  Widget build(BuildContext context) {
    final map = effectiveShortcuts(
      context.watch<SettingsCubit>().state.shortcuts,
    );
    const fixed = <(String, String)>[
      ('Ctrl+F', 'shortcut.find'),
      ('Ctrl+G', 'shortcut.goToLine'),
      ('Tab / Shift+Tab', 'shortcut.indent'),
    ];
    Widget row(String keys, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              keys,
              style: context.mono,
              textDirection: TextDirection.ltr,
            ),
          ),
          Expanded(child: Text(label, style: context.body)),
        ],
      ),
    );
    return _Section(
      title: context.t('settings.keyboard'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.t('settings.shortcutsEditable'),
              style: context.secondary,
            ),
          ),
        ),
        for (final a in ShortcutAction.values)
          row(map[a]!.display(), context.t('shortcuts.action.${a.name}')),
        for (final i in fixed) row(i.$1, context.t(i.$2)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.keyboard_outlined, size: 16),
            label: Text(context.t('shortcuts.title')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ShortcutsPage()),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// --- Diagnostics ----------------------------------------------------------------

class _Diagnostics extends StatelessWidget {
  const _Diagnostics();

  @override
  Widget build(BuildContext context) {
    final data = context.read<AppDataService>();
    final log = context.read<AppLog>();
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 170, child: Text(k, style: context.secondary)),
          Expanded(
            child: SelectableText(
              v,
              style: context.mono.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
    return _Section(
      title: context.t('settings.diagnostics'),
      children: <Widget>[
        const SizedBox(height: 6),
        kv(context.t('settings.version'), '$appVersionLabel ($appBuild)'),
        kv(
          context.t('settings.platform'),
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        ),
        kv('Dart', Platform.version.split(' ').first),
        kv(context.t('settings.dbSchema'), '${data.schemaVersion}'),
        kv(context.t('settings.settingsSchema'), '$settingsSchemaVersion'),
        kv(
          context.t('settings.secureStorage'),
          context.t(
            data.secretsPersistent
                ? 'settings.secureOk'
                : 'settings.secureMemory',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => showTextDialog(
                  context,
                  title: context.t('settings.exportLog'),
                  text: log.entries.isEmpty
                      ? context.t('settings.logEmpty')
                      : log.export(),
                ),
                child: Text(context.t('settings.exportLog')),
              ),
              OutlinedButton(
                onPressed: log.clear,
                child: Text(context.t('settings.clearLog')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- About ----------------------------------------------------------------------

class _About extends StatelessWidget {
  const _About();

  static const List<String> _packages = <String>[
    'flutter_bloc',
    'intl',
    'shared_preferences',
    'sqlite3',
    'path_provider',
    'path',
    'flutter_secure_storage',
    'url_launcher',
    'crypto',
    'app_links',
    'Vazirmatn (OFL)',
    'Inter (OFL)',
    'JetBrains Mono (OFL)',
  ];

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // No browser available: nothing to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: context.t('settings.about'),
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const BrandLogo(size: 48),
          title: Text(
            '$appName $appVersionLabel',
            style: context.body.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(context.t('about.tagline'), style: context.secondary),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.license')),
          subtitle: const Text('MIT · Uniqueone'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.repository')),
          subtitle: Text(repositoryUrl, style: context.secondary),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _open(repositoryUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.madeBy', <String>[authorName])),
          subtitle: Text(authorUrl, style: context.secondary),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _open(authorUrl),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('update.auto')),
          subtitle: Text(context.t('update.autoHelp')),
          value: context.watch<SettingsCubit>().state.checkUpdates,
          onChanged: (v) => context.read<SettingsCubit>().update(
            (x) => x.copyWith(checkUpdates: v),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('update.checkNow')),
          trailing: const Icon(Icons.system_update_alt, size: 18),
          onTap: () => checkForUpdatesManually(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.notices')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: appName,
            applicationVersion: appVersionLabel,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.privacy')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showTextDialog(
            context,
            title: context.t('about.privacy'),
            text: context.t('privacy.body'),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.changelog')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showTextDialog(
            context,
            title: context.t('about.changelog'),
            text: context.t('about.changelogBody'),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('settings.tour')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await context.read<SettingsCubit>().update(
              (s) => s.copyWith(onboardingDone: false),
            );
            if (context.mounted) {
              Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.acknowledgments')),
          subtitle: Text(_packages.join(', '), style: context.secondary),
        ),
      ],
    );
  }
}

/// Custom CA and client certificate (mTLS). Files are referenced by path and
/// never copied; the key password goes to the secret store.
class _CertFields extends StatefulWidget {
  const _CertFields({required this.s});
  final AppSettings s;

  @override
  State<_CertFields> createState() => _CertFieldsState();
}

class _CertFieldsState extends State<_CertFields> {
  late final TextEditingController _ca = TextEditingController(
    text: widget.s.caCertPath,
  );
  late final TextEditingController _cert = TextEditingController(
    text: widget.s.clientCertPath,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.s.clientKeyPath,
  );
  final TextEditingController _password = TextEditingController();
  bool _passwordLoaded = false;

  @override
  void initState() {
    super.initState();
    context.read<SecretStore>().read(kClientKeyPasswordSecret).then((v) {
      if (!mounted) return;
      _password.text = v ?? '';
      setState(() => _passwordLoaded = true);
    });
  }

  @override
  void dispose() {
    _ca.dispose();
    _cert.dispose();
    _key.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _browse(
    TextEditingController target,
    AppSettings Function(AppSettings, String) apply,
  ) async {
    final cubit = context.read<SettingsCubit>();
    final picked = await context.read<FileService>().pickFile(
      extensions: <String>['pem', 'crt', 'cer', 'key'],
    );
    if (picked == null) return;
    target.text = picked.path;
    await cubit.update((x) => apply(x, picked.path));
  }

  Widget _pathRow(
    String label,
    TextEditingController c,
    AppSettings Function(AppSettings, String) apply,
  ) {
    final cubit = context.read<SettingsCubit>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: c,
              style: context.mono,
              decoration: InputDecoration(labelText: label),
              onChanged: (v) => cubit.update((x) => apply(x, v.trim())),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _browse(c, apply),
            child: Text(context.t('ie.browse')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Field(
      label: context.t('settings.certs'),
      help: context.t('settings.certsHelp'),
      child: Column(
        children: <Widget>[
          _pathRow(
            context.t('settings.caCert'),
            _ca,
            (x, v) => x.copyWith(caCertPath: v),
          ),
          _pathRow(
            context.t('settings.clientCert'),
            _cert,
            (x, v) => x.copyWith(clientCertPath: v),
          ),
          _pathRow(
            context.t('settings.clientKey'),
            _key,
            (x, v) => x.copyWith(clientKeyPath: v),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            enabled: _passwordLoaded,
            enableSuggestions: false,
            autocorrect: false,
            style: context.mono,
            decoration: InputDecoration(
              labelText: context.t('settings.clientKeyPassword'),
            ),
            onChanged: (v) {
              final store = context.read<SecretStore>();
              if (v.isEmpty) {
                store.delete(kClientKeyPasswordSecret);
              } else {
                store.write(kClientKeyPasswordSecret, v);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// A read-only field that shows a clock time and opens the time picker.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onPicked,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return Pressable(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onPicked(picked.hour * 60 + picked.minute);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(Icons.schedule, size: 18, color: c.textSecondary),
        ),
        child: Text(
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          style: context.mono,
        ),
      ),
    );
  }
}
