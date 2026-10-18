import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';

abstract interface class SettingsRepository {
  AppSettings load();
  Future<void> save(AppSettings settings);
  Future<void> reset();
}

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  static const String key = 'postbox.settings';
  final SharedPreferences _prefs;

  @override
  AppSettings load() {
    final raw = _prefs.getString(key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _prefs.setString(key, jsonEncode(settings.toJson()));
  }

  @override
  Future<void> reset() async {
    await _prefs.remove(key);
  }
}

/// For tests and fallbacks.
class MemorySettingsRepository implements SettingsRepository {
  AppSettings _value = const AppSettings();

  @override
  AppSettings load() => _value;

  @override
  Future<void> save(AppSettings settings) async => _value = settings;

  @override
  Future<void> reset() async => _value = const AppSettings();
}
