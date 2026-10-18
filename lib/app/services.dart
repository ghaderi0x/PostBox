import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/util/app_log.dart';
import '../features/auth/oauth_service.dart';
import '../features/collections/data/collection_repository.dart';
import '../features/data/app_data_service.dart';
import '../features/environments/data/environment_repository.dart';
import '../features/history/data/history_repository.dart';
import '../features/http/application/request_executor.dart';
import '../features/http/data/io_http_engine.dart';
import '../features/http/domain/http_engine.dart';
import '../features/persistence/app_database.dart';
import '../features/secrets/secret_store.dart';
import '../features/secrets/secret_vault.dart';
import '../features/settings/data/settings_repository.dart';

/// Composition root: builds every long-lived dependency once.
class AppServices {
  AppServices({
    required this.log,
    required this.settingsRepository,
    required this.database,
    required this.secrets,
    required this.engine,
    required this.oauth,
  })  : vault = SecretVault(secrets),
        collections = SqliteCollectionRepository(database),
        history = SqliteHistoryRepository(database),
        environments = SqliteEnvironmentRepository(database) {
    executor = RequestExecutor(engine: engine, oauth: oauth);
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
  late final RequestExecutor executor;
  late final AppDataService data;

  static Future<AppServices> create() async {
    final log = AppLog();
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    final db = AppDatabase.open(p.join(dir.path, 'postbox.db'), log: log);
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
    );
  }

  /// In-memory services for tests.
  factory AppServices.inMemory({HttpEngine engine = const IoHttpEngine(), UrlLauncher? launcher}) {
    final log = AppLog();
    return AppServices(
      log: log,
      settingsRepository: MemorySettingsRepository(),
      database: AppDatabase.openInMemory(log: log),
      secrets: MemorySecretStore(),
      engine: engine,
      oauth: OAuthService(engine: engine, launcher: launcher ?? (_) async => false),
    );
  }
}
