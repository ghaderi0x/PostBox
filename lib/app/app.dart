import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/design/theme.dart';
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
import '../features/workspace/application/workspace_cubit.dart';
import '../l10n/strings.dart';
import '../ui/app_shell.dart';
import 'services.dart';

class PostBoxApp extends StatefulWidget {
  const PostBoxApp({super.key, required this.services});

  final AppServices services;

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
    _workspace.newTab();
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
            final sysCode = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
            final code = locale?.languageCode ?? (sysCode == 'fa' ? 'fa' : 'en');
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
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(base * s.fontScale),
                    disableAnimations: s.reducedMotion || mq.disableAnimations,
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: _ready
                  ? const AppShell()
                  : const Scaffold(body: Center(child: CircularProgressIndicator())),
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'PostBox could not start.\n\n${error.runtimeType}: $error\n\n'
              'Check that the app data folder is writable and try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
