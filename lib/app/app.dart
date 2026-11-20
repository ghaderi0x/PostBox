import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/design/presets.dart';
import '../core/design/theme.dart';
import '../core/platform/file_service.dart';
import '../core/platform/share_intent_service.dart';
import '../core/util/app_log.dart';
import '../features/auth/oauth_service.dart';
import '../features/collections/application/collections_cubit.dart';
import '../features/data/app_data_service.dart';
import '../features/environments/application/environments_cubit.dart';
import '../features/history/application/history_cubit.dart';
import '../features/runner/application/runner_cubit.dart';
import '../features/secrets/secret_store.dart';
import '../features/settings/application/settings_cubit.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/templates/request_templates.dart';
import '../features/workspaces/workspace_registry.dart';
import '../features/workspace/application/workspace_cubit.dart';
import '../l10n/strings.dart';
import '../ui/app_shell.dart';
import '../ui/onboarding/onboarding_page.dart';
import '../ui/splash/splash_screen.dart';
import 'services.dart';

class PostBoxApp extends StatefulWidget {
  const PostBoxApp({
    super.key,
    required this.services,
    required this.workspaces,
  });

  final AppServices services;
  final WorkspaceManager workspaces;

  @override
  State<PostBoxApp> createState() => _PostBoxAppState();
}

class _PostBoxAppState extends State<PostBoxApp> {
  late final SettingsCubit _settings;
  late final EnvironmentsCubit _envs;
  late final CollectionsCubit _collections;
  late final HistoryCubit _history;
  late final WorkspaceCubit _workspace;
  late final RunnerCubit _runner;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final s = widget.services;
    _settings = SettingsCubit(s.settingsRepository);
    _envs = EnvironmentsCubit(s.environments, s.vault);
    _collections = CollectionsCubit(s.collections, s.vault);
    _history = HistoryCubit(s.history);
    _workspace = WorkspaceCubit(
      collections: _collections,
      environments: _envs,
      settings: _settings,
      history: _history,
      executor: s.executor,
      log: s.log,
      session: s.session,
    );
    _runner = RunnerCubit(
      collections: _collections,
      environments: _envs,
      settings: _settings,
      executor: s.executor,
    );
    _load();
  }

  Future<void> _load() async {
    await _collections.load();
    await _envs.load();
    _history.prune(_settings.state);
    var restored = false;
    if (_settings.state.restoreWorkspace) {
      restored = await _workspace.restoreSession();
    }
    if (!restored) _workspace.newTab();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _workspace.close();
    _runner.close();
    _history.close();
    _collections.close();
    _envs.close();
    _settings.close();
    super.dispose();
  }

  Locale? _effectiveLocale(AppSettings s) {
    switch (s.language) {
      case AppLanguage.en:
        return const Locale('en');
      case AppLanguage.fa:
        return const Locale('fa');
      case AppLanguage.system:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        RepositoryProvider<AppLog>.value(value: services.log),
        RepositoryProvider<OAuthService>.value(value: services.oauth),
        RepositoryProvider<AppDataService>.value(value: services.data),
        RepositoryProvider<SecretStore>.value(value: services.secrets),
        RepositoryProvider<FileService>.value(value: services.files),
        RepositoryProvider<ShareIntentService>.value(value: services.share),
        RepositoryProvider<TemplateStore>.value(value: services.templates),
        RepositoryProvider<WorkspaceManager>.value(value: widget.workspaces),
        RepositoryProvider<AppServices>.value(value: services),
      ],
      child: MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<SettingsCubit>.value(value: _settings),
          BlocProvider<EnvironmentsCubit>.value(value: _envs),
          BlocProvider<CollectionsCubit>.value(value: _collections),
          BlocProvider<HistoryCubit>.value(value: _history),
          BlocProvider<WorkspaceCubit>.value(value: _workspace),
          BlocProvider<RunnerCubit>.value(value: _runner),
        ],
        child: BlocBuilder<SettingsCubit, AppSettings>(
          builder: (context, s) {
            final locale = _effectiveLocale(s);
            final sysCode =
                WidgetsBinding.instance.platformDispatcher.locale.languageCode;
            final code =
                locale?.languageCode ?? (sysCode == 'fa' ? 'fa' : 'en');
            final persianUi = code == 'fa';
            ThemeData theme(Brightness b) =>
                buildTheme(brightness: b, settings: s, persianUi: persianUi);
            final mode = switch (s.themeMode) {
              AppThemeMode.system => ThemeMode.system,
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
            };
            return MaterialApp(
              title: 'PostBox',
              debugShowCheckedModeBanner: false,
              theme: theme(Brightness.light),
              darkTheme: theme(Brightness.dark),
              themeMode: mode,
              locale: locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                final base = mq.textScaler.scale(14) / 14;
                final scaled = MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(base * s.fontScale),
                    disableAnimations: s.reducedMotion || mq.disableAnimations,
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
                if (!Platform.isWindows) return scaled;
                // Window border in the accent colour (Windows only).
                final accent = buildColors(
                  s.themePreset,
                  Theme.of(context).brightness,
                  accentOverride: s.accentOverride,
                  surface: s.surfaceStyle,
                ).accent;
                return DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: accent.withAlpha(200),
                      width: 1.5,
                    ),
                  ),
                  child: scaled,
                );
              },
              home: !_ready
                  ? const SplashScreen(animate: false)
                  : (s.onboardingDone
                        ? const AppShell()
                        : const OnboardingPage()),
            );
          },
        ),
      ),
    );
  }
}

/// Shown when startup fails (for example the database cannot be opened).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final text = '${error.runtimeType}: $error';
    // Platform errors can contain very long stack traces; keep the screen readable.
    final shown = text.length > 700 ? '${text.substring(0, 700)}…' : text;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'PostBox could not start.\n\n$shown\n\n'
                'If this mentions NoSuchMethodError in a plugin, the release build was '
                'probably shrunk by R8: see docs/RELEASE.md, section "Startup crash after '
                'a release build".',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
