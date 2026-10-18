import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_info.dart';
import '../../core/design/presets.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/app_log.dart';
import '../../features/collections/application/collections_cubit.dart';
import '../../features/data/app_data_service.dart';
import '../../features/environments/application/environments_cubit.dart';
import '../../features/history/application/history_cubit.dart';
import '../../features/http/domain/http_engine.dart';
import '../../features/settings/application/settings_cubit.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../features/workspace/application/workspace_cubit.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';
import '../widgets/key_value_editor.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.title'))),
      body: BlocBuilder<SettingsCubit, AppSettings>(builder: (context, s) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: <Widget>[
                _Appearance(s: s),
                _Language(s: s),
                _Requests(s: s),
                _EditorSection(s: s),
                _Privacy(s: s),
                const _Keyboard(),
                const _Diagnostics(),
                const _About(),
              ],
            ),
          ),
        );
      }),
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
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: context.pageTitle),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(children: children),
          ),
        ],
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

Widget _switch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged, {String? help}) {
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label, style: context.body),
    subtitle: help == null ? null : Text(help, style: context.secondary),
    value: value,
    onChanged: onChanged,
  );
}

Widget _segmented<T>(T value, Map<T, String> options, ValueChanged<T> onChanged) {
  return SegmentedButton<T>(
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    showSelectedIcon: false,
    segments: <ButtonSegment<T>>[
      for (final e in options.entries) ButtonSegment<T>(value: e.key, label: Text(e.value)),
    ],
    selected: <T>{value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}

class _IntField extends StatefulWidget {
  const _IntField({required this.value, required this.min, required this.max, required this.onChanged, this.suffix});
  final int value;
  final int min;
  final int max;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');
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
    final hex = await promptText(context, title: context.t('settings.customAccent'), label: 'RRGGBB', initial: '');
    if (hex == null || !context.mounted) return;
    final clean = hex.trim().replaceFirst('#', '');
    final v = int.tryParse(clean, radix: 16);
    if (clean.length != 6 || v == null) {
      await showToast(context, context.t('settings.badHex'));
      return;
    }
    await context.read<SettingsCubit>().update((x) => x.copyWith(accentOverride: 0xFF000000 | v));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    final c = context.colors;
    return _Section(title: context.t('settings.appearance'), children: <Widget>[
      _Field(
        label: context.t('settings.themeMode'),
        child: _segmented<AppThemeMode>(s.themeMode, <AppThemeMode, String>{
          AppThemeMode.system: context.t('settings.system'),
          AppThemeMode.light: context.t('settings.light'),
          AppThemeMode.dark: context.t('settings.dark'),
        }, (v) => cubit.update((x) => x.copyWith(themeMode: v))),
      ),
      _Field(
        label: context.t('settings.preset'),
        child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final p in ThemePreset.values)
            ChoiceChip(
              avatar: CircleAvatar(
                radius: 7,
                backgroundColor: buildColors(p, Theme.of(context).brightness).accent,
              ),
              label: Text(context.t('preset.${p.name}')),
              selected: s.themePreset == p,
              onSelected: (_) => cubit.update((x) => x.copyWith(themePreset: p)),
            ),
        ]),
      ),
      _Field(
        label: context.t('settings.accent'),
        help: context.t('settings.accentHelp'),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          ChoiceChip(
            label: Text(context.t('settings.presetAccent')),
            selected: s.accentOverride == null,
            onSelected: (_) => cubit.update((x) => x.copyWith(clearAccent: true)),
          ),
          for (final a in kAccentSwatches)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => cubit.update((x) => x.copyWith(accentOverride: a)),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(a),
                  shape: BoxShape.circle,
                  border: Border.all(color: s.accentOverride == a ? c.textPrimary : c.border, width: s.accentOverride == a ? 3 : 1),
                ),
              ),
            ),
          OutlinedButton(onPressed: () => _customAccent(context), child: Text(context.t('settings.custom'))),
        ]),
      ),
      _Field(
        label: context.t('settings.surface'),
        child: _segmented<SurfaceStyle>(s.surfaceStyle, <SurfaceStyle, String>{
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
    ]);
  }
}

// --- Language and accessibility ------------------------------------------

class _Language extends StatelessWidget {
  const _Language({required this.s});
  final AppSettings s;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Section(title: context.t('settings.language'), children: <Widget>[
      _Field(
        label: context.t('settings.languageLabel'),
        child: _segmented<AppLanguage>(s.language, <AppLanguage, String>{
          AppLanguage.system: context.t('settings.system'),
          AppLanguage.en: 'English',
          AppLanguage.fa: 'فارسی',
        }, (v) => cubit.update((x) => x.copyWith(language: v))),
      ),
      _switch(context, context.t('settings.persianDigits'), s.persianDigits,
          (v) => cubit.update((x) => x.copyWith(persianDigits: v)),
          help: context.t('settings.persianDigitsHelp')),
      _switch(context, context.t('settings.jalali'), s.jalaliDates,
          (v) => cubit.update((x) => x.copyWith(jalaliDates: v)),
          help: context.t('settings.jalaliHelp')),
      _Field(
        label: '${context.t('settings.fontScale')}: ${(s.fontScale * 100).round()}%',
        child: Slider(
          value: s.fontScale,
          min: 0.8,
          max: 1.6,
          divisions: 16,
          onChanged: (v) => cubit.update((x) => x.copyWith(fontScale: double.parse(v.toStringAsFixed(2)))),
        ),
      ),
      _switch(context, context.t('settings.reducedMotion'), s.reducedMotion,
          (v) => cubit.update((x) => x.copyWith(reducedMotion: v)),
          help: context.t('settings.reducedMotionHelp')),
    ]);
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
  late final TextEditingController _proxy = TextEditingController(text: widget.s.proxy);
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
    return _Section(title: context.t('settings.requests'), children: <Widget>[
      _Field(
        label: context.t('settings.defaultMethod'),
        child: DropdownButton<String>(
          value: kHttpMethods.contains(s.defaultMethod) ? s.defaultMethod : null,
          hint: Text(s.defaultMethod),
          items: <DropdownMenuItem<String>>[
            for (final m in kHttpMethods) DropdownMenuItem<String>(value: m, child: Text(m)),
          ],
          onChanged: (v) {
            if (v != null) cubit.update((x) => x.copyWith(defaultMethod: v));
          },
        ),
      ),
      _Field(
        label: context.t('settings.timeout'),
        child: _IntField(value: s.timeoutSeconds, min: 1, max: 600, suffix: 's',
            onChanged: (v) => cubit.update((x) => x.copyWith(timeoutSeconds: v))),
      ),
      _Field(
        label: context.t('settings.redirects'),
        help: context.t('settings.redirectsHelp'),
        child: DropdownButton<RedirectPolicy>(
          value: s.redirectPolicy,
          items: <DropdownMenuItem<RedirectPolicy>>[
            for (final p in RedirectPolicy.values)
              DropdownMenuItem<RedirectPolicy>(value: p, child: Text(context.t('redirect.${p.name}'))),
          ],
          onChanged: (v) {
            if (v != null) cubit.update((x) => x.copyWith(redirectPolicy: v));
          },
        ),
      ),
      _Field(
        label: context.t('settings.maxRedirects'),
        child: _IntField(value: s.maxRedirects, min: 0, max: 30,
            onChanged: (v) => cubit.update((x) => x.copyWith(maxRedirects: v))),
      ),
      _Field(
        label: context.t('settings.proxy'),
        help: context.t('settings.proxyHelp'),
        child: SizedBox(
          width: 280,
          child: TextField(
            controller: _proxy,
            style: context.mono,
            decoration: InputDecoration(hintText: '127.0.0.1:8080', errorText: _proxyError),
            onChanged: (v) {
              final t = v.trim();
              if (isValidProxy(t)) {
                setState(() => _proxyError = null);
                cubit.update((x) => x.copyWith(proxy: t));
              } else {
                setState(() => _proxyError = context.t('settings.proxyInvalid'));
              }
            },
          ),
        ),
      ),
      _switch(context, context.t('settings.allowInvalidTls'), s.allowInvalidCertificates, _toggleTls,
          help: context.t('settings.allowInvalidTlsHelp')),
      if (s.allowInvalidCertificates)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InfoBanner(context.t('settings.tlsWarning'), warning: true),
        ),
      _Field(
        label: context.t('settings.maxResponse'),
        child: _IntField(value: s.maxResponseMb, min: 1, max: 200, suffix: 'MB',
            onChanged: (v) => cubit.update((x) => x.copyWith(maxResponseMb: v))),
      ),
      _Field(
        label: context.t('settings.maxRequest'),
        child: _IntField(value: s.maxRequestMb, min: 1, max: 100, suffix: 'MB',
            onChanged: (v) => cubit.update((x) => x.copyWith(maxRequestMb: v))),
      ),
      _Field(
        label: context.t('settings.defaultHeaders'),
        help: context.t('settings.defaultHeadersHelp'),
        child: Container(
          height: (s.defaultHeaders.length + 1) * 52.0 + 24,
          constraints: const BoxConstraints(minHeight: 90),
          decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
          child: KeyValueEditor(
            items: s.defaultHeaders,
            keyHint: 'Header',
            onChanged: (v) => cubit.update((x) => x.copyWith(defaultHeaders: v)),
          ),
        ),
      ),
    ]);
  }
}

// --- Editor -----------------------------------------------------------------

class _EditorSection extends StatelessWidget {
  const _EditorSection({required this.s});
  final AppSettings s;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Section(title: context.t('settings.editor'), children: <Widget>[
      _switch(context, context.t('settings.wordWrap'), s.editorWordWrap, (v) => cubit.update((x) => x.copyWith(editorWordWrap: v))),
      _switch(context, context.t('settings.lineNumbers'), s.editorLineNumbers, (v) => cubit.update((x) => x.copyWith(editorLineNumbers: v))),
      _switch(context, context.t('settings.autoClose'), s.editorAutoClose, (v) => cubit.update((x) => x.copyWith(editorAutoClose: v))),
      _switch(context, context.t('settings.highlightVars'), s.editorHighlightVariables,
          (v) => cubit.update((x) => x.copyWith(editorHighlightVariables: v))),
      _Field(
        label: '${context.t('settings.editorFontSize')}: ${s.editorFontSize.round()}',
        child: Slider(
          value: s.editorFontSize,
          min: 10,
          max: 24,
          divisions: 14,
          onChanged: (v) => cubit.update((x) => x.copyWith(editorFontSize: v.roundToDouble())),
        ),
      ),
      _Field(
        label: context.t('settings.tabSize'),
        child: _segmented<int>(s.editorTabSize, const <int, String>{2: '2', 4: '4'},
            (v) => cubit.update((x) => x.copyWith(editorTabSize: v))),
      ),
    ]);
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
    if (context.mounted) await showToast(context, context.t('settings.clearedAll'));
  }

  Future<void> _export(BuildContext context) async {
    final text = context.read<SettingsCubit>().exportJson();
    await showTextDialog(context, title: context.t('settings.exportSettings'), text: text);
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
    await showToast(context, err == null ? context.t('settings.imported') : context.t('settings.importFailed.$err'));
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: context.t('settings.resetTitle'),
      message: context.t('settings.resetMsg'),
      confirmLabel: context.t('settings.reset'),
      force: true,
    );
    if (ok && context.mounted) await context.read<SettingsCubit>().resetToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Section(title: context.t('settings.privacy'), children: <Widget>[
      _switch(context, context.t('settings.persistHistory'), s.persistHistory,
          (v) => cubit.update((x) => x.copyWith(persistHistory: v))),
      _switch(context, context.t('settings.omitSensitive'), s.omitSensitiveInHistory,
          (v) => cubit.update((x) => x.copyWith(omitSensitiveInHistory: v)),
          help: context.t('settings.omitSensitiveHelp')),
      _Field(
        label: context.t('settings.retention'),
        child: DropdownButton<int>(
          value: const <int>[0, 7, 30, 90, 365].contains(s.historyRetentionDays) ? s.historyRetentionDays : null,
          hint: Text('${s.historyRetentionDays}'),
          items: <DropdownMenuItem<int>>[
            DropdownMenuItem<int>(value: 7, child: Text(context.t('settings.days', <String>['7']))),
            DropdownMenuItem<int>(value: 30, child: Text(context.t('settings.days', <String>['30']))),
            DropdownMenuItem<int>(value: 90, child: Text(context.t('settings.days', <String>['90']))),
            DropdownMenuItem<int>(value: 365, child: Text(context.t('settings.days', <String>['365']))),
            DropdownMenuItem<int>(value: 0, child: Text(context.t('settings.forever'))),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await cubit.update((x) => x.copyWith(historyRetentionDays: v));
            if (context.mounted) context.read<HistoryCubit>().prune(cubit.state);
          },
        ),
      ),
      _Field(
        label: context.t('settings.maxHistory'),
        child: _IntField(value: s.historyMaxEntries, min: 10, max: 10000, onChanged: (v) async {
          await cubit.update((x) => x.copyWith(historyMaxEntries: v));
          if (context.mounted) context.read<HistoryCubit>().prune(cubit.state);
        }),
      ),
      _switch(context, context.t('settings.confirmDestructive'), s.confirmDestructive,
          (v) => cubit.update((x) => x.copyWith(confirmDestructive: v))),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: InfoBanner(context.t('settings.noTelemetry')),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          OutlinedButton(onPressed: () => _clearHistory(context), child: Text(context.t('history.clear'))),
          OutlinedButton(onPressed: () => _export(context), child: Text(context.t('settings.exportSettings'))),
          OutlinedButton(onPressed: () => _import(context), child: Text(context.t('settings.importSettings'))),
          OutlinedButton(onPressed: () => _reset(context), child: Text(context.t('settings.reset'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => _clearAll(context),
            child: Text(context.t('settings.clearAll')),
          ),
        ]),
      ),
    ]);
  }
}

// --- Keyboard ---------------------------------------------------------------

class _Keyboard extends StatelessWidget {
  const _Keyboard();

  @override
  Widget build(BuildContext context) {
    const items = <(String, String)>[
      ('Ctrl+Enter', 'shortcut.send'),
      ('Ctrl+S', 'shortcut.save'),
      ('Ctrl+K', 'shortcut.palette'),
      ('Ctrl+T', 'shortcut.newTab'),
      ('Ctrl+W', 'shortcut.closeTab'),
      ('Ctrl+F', 'shortcut.find'),
      ('Ctrl+G', 'shortcut.goToLine'),
      ('Tab / Shift+Tab', 'shortcut.indent'),
    ];
    return _Section(title: context.t('settings.keyboard'), children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(context.t('settings.shortcutsFixed'), style: context.secondary),
        ),
      ),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: <Widget>[
            SizedBox(width: 150, child: Text(i.$1, style: context.mono, textDirection: TextDirection.ltr)),
            Expanded(child: Text(context.t(i.$2), style: context.body)),
          ]),
        ),
      const SizedBox(height: 8),
    ]);
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SizedBox(width: 170, child: Text(k, style: context.secondary)),
            Expanded(child: SelectableText(v, style: context.mono.copyWith(fontSize: 12.5))),
          ]),
        );
    return _Section(title: context.t('settings.diagnostics'), children: <Widget>[
      const SizedBox(height: 6),
      kv(context.t('settings.version'), '$appVersion ($appBuild)'),
      kv(context.t('settings.platform'), '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
      kv('Dart', Platform.version.split(' ').first),
      kv(context.t('settings.dbSchema'), '${data.schemaVersion}'),
      kv(context.t('settings.settingsSchema'), '$settingsSchemaVersion'),
      kv(context.t('settings.secureStorage'), context.t(data.secretsPersistent ? 'settings.secureOk' : 'settings.secureMemory')),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          OutlinedButton(
            onPressed: () => showTextDialog(
              context,
              title: context.t('settings.exportLog'),
              text: log.entries.isEmpty ? context.t('settings.logEmpty') : log.export(),
            ),
            child: Text(context.t('settings.exportLog')),
          ),
          OutlinedButton(onPressed: log.clear, child: Text(context.t('settings.clearLog'))),
        ]),
      ),
    ]);
  }
}

// --- About ----------------------------------------------------------------------

class _About extends StatelessWidget {
  const _About();

  static const List<String> _packages = <String>[
    'flutter_bloc', 'intl', 'shared_preferences', 'sqlite3', 'path_provider', 'path',
    'flutter_secure_storage', 'url_launcher', 'crypto', 'app_links',
    'Vazirmatn (OFL)', 'Inter (OFL)', 'JetBrains Mono (OFL)',
  ];

  @override
  Widget build(BuildContext context) {
    return _Section(title: context.t('settings.about'), children: <Widget>[
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('$appName $appVersion', style: context.body.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(context.t('about.tagline'), style: context.secondary),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.t('about.license')),
        subtitle: const Text('MIT · Uniqueone'),
      ),
      if (repositoryUrl.isNotEmpty)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('about.repository')),
          subtitle: SelectableText(repositoryUrl),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.t('about.notices')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showLicensePage(context: context, applicationName: appName, applicationVersion: appVersion),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.t('about.privacy')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showTextDialog(context, title: context.t('about.privacy'), text: context.t('privacy.body')),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.t('about.changelog')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showTextDialog(context, title: context.t('about.changelog'), text: context.t('about.changelogBody')),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.t('about.acknowledgments')),
        subtitle: Text(_packages.join(', '), style: context.secondary),
      ),
    ]);
  }
}
