import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

class SettingsCubit extends Cubit<AppSettings> {
  SettingsCubit(this._repo) : super(_repo.load());

  final SettingsRepository _repo;

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    // Round-trip through JSON so every write is validated and clamped.
    final next = AppSettings.fromJson(change(state).toJson());
    emit(next);
    await _repo.save(next);
  }

  /// Returns an error code, or null on success.
  Future<String?> importJson(String text) async {
    final r = AppSettings.tryParse(text);
    if (r.settings == null) return r.error;
    emit(r.settings!);
    await _repo.save(r.settings!);
    return null;
  }

  String exportJson() => state.toJsonString(redactSensitive: true);

  Future<void> resetToDefaults() async {
    await _repo.reset();
    emit(const AppSettings());
  }
}
