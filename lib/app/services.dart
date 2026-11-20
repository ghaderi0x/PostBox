import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/platform/file_service.dart';
import '../core/platform/share_intent_service.dart';
import '../core/util/app_log.dart';
import '../features/auth/oauth_service.dart';
import '../features/collections/data/collection_repository.dart';
import '../features/data/app_data_service.dart';
import '../features/environments/data/environment_repository.dart';
import '../features/history/data/history_repository.dart';
import '../features/http/application/request_executor.dart';
import '../features/http/data/io_http_engine.dart';
import '../features/http/data/cookie_store.dart';
import '../features/http/domain/cookie_jar.dart';
import '../features/http/domain/http_engine.dart';
import '../features/persistence/app_database.dart';
import '../features/secrets/secret_store.dart';
import '../features/secrets/secret_vault.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/templates/request_templates.dart';
import '../features/workspace/data/session_store.dart';
import '../features/workspaces/workspace_registry.dart';

/// Composition root: builds every long-lived dependency once.
class AppServices {
  AppServices({
    required this.log,
    required this.settingsRepository,
    required this.database,
    required this.secrets,
    required this.engine,
    required this.oauth,
    this.files = const NativeFileService(),
    this.workspaceId = kDefaultWorkspaceId,
    this.enableFileDrop = true,
    this.enableUpdateCheck = true,
    this.splashMinimum = const Duration(milliseconds: 1100),
  }) : vault = SecretVault(secrets),
       collections = SqliteCollectionRepository(database),
       history = SqliteHistoryRepository(database),
       environments = SqliteEnvironmentRepository(database),
       session = SessionStore(database),
       templates = TemplateStore(database) {
    cookieJar = CookieJarImpl(persistence: SqliteCookiePersistence(database));
    executor = RequestExecutor(
      engine: engine,
      oauth: oauth,
      cookieJar: cookieJar,
      secrets: secrets,
    );
    data = AppDataService(database: database, secrets: secrets);
  }

  final AppLog log;
  final SettingsRepository settingsRepository;
  final AppDatabase database;
  final SecretStore secrets;
  final SecretVault vault;
  final HttpEngine engine;
  final OAuthService oauth;
  final CollectionRepository collections;
  final HistoryRepository history;
  final EnvironmentRepository environments;
  final FileService files;
  final String workspaceId;

  /// Accept files dropped on the window (needs the desktop_drop plugin, so
  /// widget tests turn it off).
  final bool enableFileDrop;

  /// Look for a newer GitHub release at start-up. Off in tests.
  final bool enableUpdateCheck;

  /// The splash screen stays at least this long at start-up so it does not
  /// flash. Zero in tests.
  final Duration splashMinimum;
  final SessionStore session;
  final TemplateStore templates;
  late final CookieJar cookieJar;
  late final RequestExecutor executor;
  late final AppDataService data;
  final ShareIntentService share = ShareIntentService();

  /// Releases the workspace database. Call after the UI no longer uses it.
  void close() {
    share.dispose();
    database.close();
  }

  static Future<AppServices> create({WorkspaceRegistry? registry}) async {
    final log = AppLog();
    final reg = registry ?? await WorkspaceRegistry.load();
    final workspace = reg.active;
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    final db = AppDatabase.open(p.join(dir.path, workspace.file), log: log);
    const engine = IoHttpEngine();
    final oauth = OAuthService(
      engine: engine,
      launcher: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );
    return AppServices(
      log: log,
      settingsRepository: PrefsSettingsRepository(prefs),
      database: db,
      secrets: GracefulSecretStore(log: log),
      engine: engine,
      oauth: oauth,
      workspaceId: workspace.id,
    );
  }

  /// In-memory services for tests.
  factory AppServices.inMemory({
    HttpEngine engine = const IoHttpEngine(),
    UrlLauncher? launcher,
    FileService? files,
  }) {
    final log = AppLog();
    return AppServices(
      log: log,
      settingsRepository: MemorySettingsRepository(),
      database: AppDatabase.openInMemory(log: log),
      secrets: MemorySecretStore(),
      engine: engine,
      oauth: OAuthService(
        engine: engine,
        launcher: launcher ?? (_) async => false,
      ),
      files: files ?? FakeFileService(),
      enableFileDrop: false,
      enableUpdateCheck: false,
      splashMinimum: Duration.zero,
    );
  }
}
