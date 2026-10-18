import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/model/key_value.dart';
import 'package:postbox/features/http/domain/http_engine.dart';
import 'package:postbox/features/settings/application/settings_cubit.dart';
import 'package:postbox/features/settings/data/settings_repository.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';

void main() {
  test('defaults are sane', () {
    const s = AppSettings();
    expect(s.themePreset, ThemePreset.orange);
    expect(s.allowInvalidCertificates, isFalse);
    expect(s.persianDigits, isFalse);
    expect(s.redirectPolicy, RedirectPolicy.always);
    expect(s.omitSensitiveInHistory, isTrue);
  });

  test('json round trip keeps every field', () {
    const s = AppSettings(
      themeMode: AppThemeMode.dark,
      themePreset: ThemePreset.violet,
      accentOverride: 0xFF112233,
      surfaceStyle: SurfaceStyle.flat,
      density: UiDensity.compact,
      fontScale: 1.25,
      reducedMotion: true,
      language: AppLanguage.fa,
      persianDigits: true,
      jalaliDates: true,
      defaultMethod: 'POST',
      timeoutSeconds: 12,
      redirectPolicy: RedirectPolicy.sameOrigin,
      maxRedirects: 4,
      proxy: 'proxy.local:3128',
      defaultHeaders: <KeyValue>[KeyValue(key: 'X-A', value: '1')],
      maxResponseMb: 5,
      maxRequestMb: 6,
      editorWordWrap: true,
      editorLineNumbers: false,
      editorFontSize: 16,
      editorTabSize: 4,
      editorAutoClose: false,
      editorHighlightVariables: false,
      persistHistory: false,
      historyRetentionDays: 7,
      historyMaxEntries: 50,
      omitSensitiveInHistory: false,
      confirmDestructive: false,
    );
    final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
  });

  test('invalid stored values fall back or are clamped', () {
    final s = AppSettings.fromJson(<String, dynamic>{
      'themeMode': 'neon',
      'fontScale': 99,
      'timeoutSeconds': -5,
      'maxRedirects': 1000,
      'proxy': 'not a proxy',
      'editorTabSize': 7,
      'editorFontSize': 2,
      'historyMaxEntries': 1,
      'defaultMethod': '  ',
      'defaultHeaders': <dynamic>[
        <String, dynamic>{'key': '', 'value': 'x'},
        <String, dynamic>{'key': 'A', 'value': 'b'},
      ],
    });
    expect(s.themeMode, AppThemeMode.system);
    expect(s.fontScale, 1.6);
    expect(s.timeoutSeconds, 1);
    expect(s.maxRedirects, 30);
    expect(s.proxy, '');
    expect(s.editorTabSize, 2);
    expect(s.editorFontSize, 10);
    expect(s.historyMaxEntries, 10);
    expect(s.defaultMethod, 'GET');
    expect(s.defaultHeaders.length, 1);
  });

  test('garbage input never throws', () {
    expect(AppSettings.fromJson(null).themePreset, ThemePreset.orange);
    expect(AppSettings.fromJson('x').timeoutSeconds, 30);
    expect(AppSettings.fromJson(<dynamic>[1, 2]).timeoutSeconds, 30);
  });

  test('tryParse reports errors', () {
    expect(AppSettings.tryParse('{bad').error, 'invalid_json');
    expect(AppSettings.tryParse('[1]').error, 'not_object');
    expect(AppSettings.tryParse('{"schemaVersion": 99}').error, 'newer_version');
    expect(AppSettings.tryParse('x' * 300000).error, 'too_large');
    expect(AppSettings.tryParse('{"themePreset":"emerald"}').settings!.themePreset, ThemePreset.emerald);
  });

  test('missing schemaVersion is migrated', () {
    expect(AppSettings.migrate(<String, dynamic>{})['schemaVersion'], 1);
  });

  test('export redacts sensitive default headers', () {
    const s = AppSettings(defaultHeaders: <KeyValue>[
      KeyValue(key: 'Authorization', value: 'Bearer top-secret'),
      KeyValue(key: 'Accept', value: 'text/plain'),
    ]);
    final text = s.toJsonString(redactSensitive: true);
    expect(text.contains('top-secret'), isFalse);
    expect(text.contains('text/plain'), isTrue);
  });

  test('proxy validation', () {
    expect(isValidProxy(''), isTrue);
    expect(isValidProxy('127.0.0.1:8080'), isTrue);
    expect(isValidProxy('host'), isFalse);
    expect(isValidProxy('http://host:80'), isFalse);
  });

  test('cubit validates, persists and resets', () async {
    final repo = MemorySettingsRepository();
    final cubit = SettingsCubit(repo);
    await cubit.update((s) => s.copyWith(timeoutSeconds: 9999, themePreset: ThemePreset.arctic));
    expect(cubit.state.timeoutSeconds, 600);
    expect(repo.load().themePreset, ThemePreset.arctic);
    await cubit.update((s) => s.copyWith(accentOverride: 0xFFAA0000));
    expect(cubit.state.accentOverride, 0xFFAA0000);
    await cubit.update((s) => s.copyWith(clearAccent: true));
    expect(cubit.state.accentOverride, isNull);
    expect(await cubit.importJson('{"themePreset":"emerald"}'), isNull);
    expect(cubit.state.themePreset, ThemePreset.emerald);
    expect(await cubit.importJson('nope'), 'invalid_json');
    await cubit.resetToDefaults();
    expect(cubit.state.themePreset, ThemePreset.orange);
    await cubit.close();
  });
}
