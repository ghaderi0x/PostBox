import '../persistence/app_database.dart';
import '../secrets/secret_store.dart';

/// Destroys local user data on request ("Clear local data").
class AppDataService {
  AppDataService({required AppDatabase database, required SecretStore secrets})
    : _db = database,
      _secrets = secrets;

  final AppDatabase _db;
  final SecretStore _secrets;

  int get schemaVersion => _db.schemaVersion;
  bool get secretsPersistent => _secrets.isPersistent;

  /// Deletes collections, requests, environments, history and all stored
  /// secrets. Settings are kept; use SettingsCubit.resetToDefaults for those.
  Future<void> clearAll() async {
    _db.clearAllData();
    await _secrets.clearAll();
  }
}
