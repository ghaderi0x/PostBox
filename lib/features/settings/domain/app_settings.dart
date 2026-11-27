import 'dart:convert';

import '../../../core/app_info.dart';
import '../../../core/model/key_value.dart';
import '../../../core/util/json_util.dart';
import '../../../core/util/redact.dart';
import '../../http/domain/http_engine.dart';

enum AppThemeMode { system, light, dark }

enum ThemePreset { orange, midnight, arctic, emerald, violet, highContrast }

enum SurfaceStyle { raised, flat }

enum UiDensity { comfortable, compact }

enum AppLanguage { system, en, fa }

/// `auto` offers HTTP/2 through ALPN on https and falls back to HTTP/1.1.
enum HttpVersionPref { http1, auto }

/// Name of the secret-store entry that holds the client key password.
const String kClientKeyPasswordSecret = 'settings.clientKeyPassword';

const List<String> kHttpMethods = <String>[
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
];

final RegExp _proxyPattern = RegExp(r'^[A-Za-z0-9.\-_]+:\d{1,5}$');

bool isValidProxy(String s) => s.isEmpty || _proxyPattern.hasMatch(s);

/// All persisted user settings. Every field here must have an effect somewhere
/// in the app; unknown or invalid stored values fall back to defaults.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.dark,
    this.themePreset = ThemePreset.orange,
    this.accentOverride,
    this.surfaceStyle = SurfaceStyle.raised,
    this.density = UiDensity.comfortable,
    this.fontScale = 1.0,
    this.reducedMotion = false,
    this.language = AppLanguage.system,
    this.persianDigits = true,
    this.jalaliDates = false,
    this.defaultMethod = 'GET',
    this.timeoutSeconds = 30,
    this.redirectPolicy = RedirectPolicy.always,
    this.maxRedirects = 10,
    this.proxy = '',
    this.allowInvalidCertificates = false,
    this.defaultHeaders = const <KeyValue>[],
    this.maxResponseMb = 10,
    this.maxRequestMb = 10,
    this.editorWordWrap = false,
    this.editorLineNumbers = true,
    this.editorFontSize = 13,
    this.editorTabSize = 2,
    this.editorAutoClose = true,
    this.editorHighlightVariables = true,
    this.persistHistory = true,
    this.historyRetentionDays = 30,
    this.historyMaxEntries = 500,
    this.omitSensitiveInHistory = true,
    this.confirmDestructive = true,
    this.onboardingDone = false,
    this.useCookieJar = true,
    this.httpVersion = HttpVersionPref.http1,
    this.clientCertPath = '',
    this.clientKeyPath = '',
    this.caCertPath = '',
    this.restoreWorkspace = true,
    this.checkUpdates = true,
    this.themeSchedule = false,
    this.darkFromMinutes = 19 * 60,
    this.darkToMinutes = 7 * 60,
    this.skippedVersion = '',
    this.shortcuts = const <String, String>{},
  });

  final AppThemeMode themeMode;
  final ThemePreset themePreset;

  /// ARGB value, or null to use the preset's accent.
  final int? accentOverride;
  final SurfaceStyle surfaceStyle;
  final UiDensity density;
  final double fontScale;
  final bool reducedMotion;
  final AppLanguage language;
  final bool persianDigits;
  final bool jalaliDates;

  final String defaultMethod;
  final int timeoutSeconds;
  final RedirectPolicy redirectPolicy;
  final int maxRedirects;
  final String proxy;
  final bool allowInvalidCertificates;
  final List<KeyValue> defaultHeaders;
  final int maxResponseMb;
  final int maxRequestMb;

  final bool editorWordWrap;
  final bool editorLineNumbers;
  final double editorFontSize;
  final int editorTabSize;
  final bool editorAutoClose;
  final bool editorHighlightVariables;

  final bool persistHistory;

  /// 0 means keep forever.
  final int historyRetentionDays;
  final int historyMaxEntries;
  final bool omitSensitiveInHistory;
  final bool confirmDestructive;

  /// False until the welcome tour was finished or skipped.
  final bool onboardingDone;

  /// Store cookies from responses and send them back (per host, per hop).
  final bool useCookieJar;
  final HttpVersionPref httpVersion;

  /// Mutual TLS and custom CA (PEM file paths). The key password lives in the
  /// secret store, see [kClientKeyPasswordSecret].
  final String clientCertPath;
  final String clientKeyPath;
  final String caCertPath;

  /// Reopen the tabs and panel layout of the last session on start.
  final bool restoreWorkspace;

  /// Switch between light and dark by the clock instead of [themeMode].
  final bool themeSchedule;

  /// Dark theme starts at this time, in minutes after midnight (0..1439).
  final int darkFromMinutes;

  /// Dark theme ends at this time, in minutes after midnight (0..1439).
  final int darkToMinutes;

  /// Ask GitHub for the newest release each time the app opens.
  final bool checkUpdates;

  /// A release the user chose to skip; it is not offered again.
  final String skippedVersion;

  /// Overrides of the default keyboard shortcuts: action name -> combo text
  /// such as `ctrl+shift+k`. Missing actions use their default.
  final Map<String, String> shortcuts;

  int get maxResponseBytes => maxResponseMb * 1024 * 1024;
  int get maxRequestBytes => maxRequestMb * 1024 * 1024;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    ThemePreset? themePreset,
    int? accentOverride,
    bool clearAccent = false,
    SurfaceStyle? surfaceStyle,
    UiDensity? density,
    double? fontScale,
    bool? reducedMotion,
    AppLanguage? language,
    bool? persianDigits,
    bool? jalaliDates,
    String? defaultMethod,
    int? timeoutSeconds,
    RedirectPolicy? redirectPolicy,
    int? maxRedirects,
    String? proxy,
    bool? allowInvalidCertificates,
    List<KeyValue>? defaultHeaders,
    int? maxResponseMb,
    int? maxRequestMb,
    bool? editorWordWrap,
    bool? editorLineNumbers,
    double? editorFontSize,
    int? editorTabSize,
    bool? editorAutoClose,
    bool? editorHighlightVariables,
    bool? persistHistory,
    int? historyRetentionDays,
    int? historyMaxEntries,
    bool? omitSensitiveInHistory,
    bool? confirmDestructive,
    bool? onboardingDone,
    bool? useCookieJar,
    HttpVersionPref? httpVersion,
    String? clientCertPath,
    String? clientKeyPath,
    String? caCertPath,
    bool? restoreWorkspace,
    bool? checkUpdates,
    bool? themeSchedule,
    int? darkFromMinutes,
    int? darkToMinutes,
    String? skippedVersion,
    Map<String, String>? shortcuts,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      themePreset: themePreset ?? this.themePreset,
      accentOverride: clearAccent
          ? null
          : (accentOverride ?? this.accentOverride),
      surfaceStyle: surfaceStyle ?? this.surfaceStyle,
      density: density ?? this.density,
      fontScale: fontScale ?? this.fontScale,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      language: language ?? this.language,
      persianDigits: persianDigits ?? this.persianDigits,
      jalaliDates: jalaliDates ?? this.jalaliDates,
      defaultMethod: defaultMethod ?? this.defaultMethod,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      redirectPolicy: redirectPolicy ?? this.redirectPolicy,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      proxy: proxy ?? this.proxy,
      allowInvalidCertificates:
          allowInvalidCertificates ?? this.allowInvalidCertificates,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      maxResponseMb: maxResponseMb ?? this.maxResponseMb,
      maxRequestMb: maxRequestMb ?? this.maxRequestMb,
      editorWordWrap: editorWordWrap ?? this.editorWordWrap,
      editorLineNumbers: editorLineNumbers ?? this.editorLineNumbers,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      editorTabSize: editorTabSize ?? this.editorTabSize,
      editorAutoClose: editorAutoClose ?? this.editorAutoClose,
      editorHighlightVariables:
          editorHighlightVariables ?? this.editorHighlightVariables,
      persistHistory: persistHistory ?? this.persistHistory,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      historyMaxEntries: historyMaxEntries ?? this.historyMaxEntries,
      omitSensitiveInHistory:
          omitSensitiveInHistory ?? this.omitSensitiveInHistory,
      confirmDestructive: confirmDestructive ?? this.confirmDestructive,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      useCookieJar: useCookieJar ?? this.useCookieJar,
      httpVersion: httpVersion ?? this.httpVersion,
      clientCertPath: clientCertPath ?? this.clientCertPath,
      clientKeyPath: clientKeyPath ?? this.clientKeyPath,
      caCertPath: caCertPath ?? this.caCertPath,
      restoreWorkspace: restoreWorkspace ?? this.restoreWorkspace,
      checkUpdates: checkUpdates ?? this.checkUpdates,
      themeSchedule: themeSchedule ?? this.themeSchedule,
      darkFromMinutes: darkFromMinutes ?? this.darkFromMinutes,
      darkToMinutes: darkToMinutes ?? this.darkToMinutes,
      skippedVersion: skippedVersion ?? this.skippedVersion,
      shortcuts: shortcuts ?? this.shortcuts,
    );
  }

  /// [redactSensitive] masks values of sensitive default headers, which is the
  /// default for settings exports.
  Map<String, dynamic> toJson({bool redactSensitive = false}) {
    final headers = defaultHeaders
        .map(
          (h) => redactSensitive && Redactor.isSensitiveHeader(h.key)
              ? h.copyWith(value: Redactor.mask).toJson()
              : h.toJson(),
        )
        .toList();
    return <String, dynamic>{
      'schemaVersion': settingsSchemaVersion,
      'themeMode': themeMode.name,
      'themePreset': themePreset.name,
      if (accentOverride != null) 'accentOverride': accentOverride,
      'surfaceStyle': surfaceStyle.name,
      'density': density.name,
      'fontScale': fontScale,
      'reducedMotion': reducedMotion,
      'language': language.name,
      'persianDigits': persianDigits,
      'jalaliDates': jalaliDates,
      'defaultMethod': defaultMethod,
      'timeoutSeconds': timeoutSeconds,
      'redirectPolicy': redirectPolicy.name,
      'maxRedirects': maxRedirects,
      'proxy': proxy,
      'allowInvalidCertificates': allowInvalidCertificates,
      'defaultHeaders': headers,
      'maxResponseMb': maxResponseMb,
      'maxRequestMb': maxRequestMb,
      'editorWordWrap': editorWordWrap,
      'editorLineNumbers': editorLineNumbers,
      'editorFontSize': editorFontSize,
      'editorTabSize': editorTabSize,
      'editorAutoClose': editorAutoClose,
      'editorHighlightVariables': editorHighlightVariables,
      'persistHistory': persistHistory,
      'historyRetentionDays': historyRetentionDays,
      'historyMaxEntries': historyMaxEntries,
      'omitSensitiveInHistory': omitSensitiveInHistory,
      'confirmDestructive': confirmDestructive,
      'onboardingDone': onboardingDone,
      'useCookieJar': useCookieJar,
      'httpVersion': httpVersion.name,
      'clientCertPath': clientCertPath,
      'clientKeyPath': clientKeyPath,
      'caCertPath': caCertPath,
      'restoreWorkspace': restoreWorkspace,
      'checkUpdates': checkUpdates,
      'themeSchedule': themeSchedule,
      'darkFromMinutes': darkFromMinutes,
      'darkToMinutes': darkToMinutes,
      'skippedVersion': skippedVersion,
      'shortcuts': shortcuts,
    };
  }

  String toJsonString({bool redactSensitive = false}) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(toJson(redactSensitive: redactSensitive));

  /// Migrates older schema versions to the current one; steps are chained.
  ///
  /// v2 (1.0.0): dark theme and Persian digits became the defaults, and the
  /// first-run screen now asks for the theme. Settings saved by earlier
  /// versions are moved to the new defaults once and the first-run screen is
  /// shown again so the theme can be chosen.
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final v = asInt(out['schemaVersion'], 0);
    if (v < 1) {
      out['schemaVersion'] = 1;
    }
    if (v < 2) {
      out['schemaVersion'] = 2;
      if (json.isNotEmpty) {
        out['themeMode'] = AppThemeMode.dark.name;
        out['persianDigits'] = true;
        out['onboardingDone'] = false;
      }
    }
    return out;
  }

  /// Lenient: never throws, clamps ranges, ignores unknown keys.
  factory AppSettings.fromJson(Object? raw) {
    const d = AppSettings();
    final j = migrate(asMap(raw));
    final method = asString(
      j['defaultMethod'],
      d.defaultMethod,
    ).trim().toUpperCase();
    final proxy = asString(j['proxy']).trim();
    final tab = asInt(j['editorTabSize'], d.editorTabSize);
    final accent = j['accentOverride'];
    final headers = KeyValue.listFromJson(
      j['defaultHeaders'],
    ).where((h) => h.key.trim().isNotEmpty).toList();
    return AppSettings(
      themeMode: enumByName(AppThemeMode.values, j['themeMode'], d.themeMode),
      themePreset: enumByName(
        ThemePreset.values,
        j['themePreset'],
        d.themePreset,
      ),
      accentOverride: accent is int ? accent : null,
      surfaceStyle: enumByName(
        SurfaceStyle.values,
        j['surfaceStyle'],
        d.surfaceStyle,
      ),
      density: enumByName(UiDensity.values, j['density'], d.density),
      fontScale: clampDouble(asDouble(j['fontScale'], d.fontScale), 0.8, 1.6),
      reducedMotion: asBool(j['reducedMotion'], d.reducedMotion),
      language: enumByName(AppLanguage.values, j['language'], d.language),
      persianDigits: asBool(j['persianDigits'], d.persianDigits),
      jalaliDates: asBool(j['jalaliDates'], d.jalaliDates),
      defaultMethod: method.isEmpty ? d.defaultMethod : method,
      timeoutSeconds: clampInt(
        asInt(j['timeoutSeconds'], d.timeoutSeconds),
        1,
        600,
      ),
      redirectPolicy: enumByName(
        RedirectPolicy.values,
        j['redirectPolicy'],
        d.redirectPolicy,
      ),
      maxRedirects: clampInt(asInt(j['maxRedirects'], d.maxRedirects), 0, 30),
      proxy: isValidProxy(proxy) ? proxy : '',
      allowInvalidCertificates: asBool(
        j['allowInvalidCertificates'],
        d.allowInvalidCertificates,
      ),
      defaultHeaders: headers,
      maxResponseMb: clampInt(
        asInt(j['maxResponseMb'], d.maxResponseMb),
        1,
        200,
      ),
      maxRequestMb: clampInt(asInt(j['maxRequestMb'], d.maxRequestMb), 1, 100),
      editorWordWrap: asBool(j['editorWordWrap'], d.editorWordWrap),
      editorLineNumbers: asBool(j['editorLineNumbers'], d.editorLineNumbers),
      editorFontSize: clampDouble(
        asDouble(j['editorFontSize'], d.editorFontSize),
        10,
        24,
      ),
      editorTabSize: tab == 4 ? 4 : 2,
      editorAutoClose: asBool(j['editorAutoClose'], d.editorAutoClose),
      editorHighlightVariables: asBool(
        j['editorHighlightVariables'],
        d.editorHighlightVariables,
      ),
      persistHistory: asBool(j['persistHistory'], d.persistHistory),
      historyRetentionDays: clampInt(
        asInt(j['historyRetentionDays'], d.historyRetentionDays),
        0,
        3650,
      ),
      historyMaxEntries: clampInt(
        asInt(j['historyMaxEntries'], d.historyMaxEntries),
        10,
        10000,
      ),
      omitSensitiveInHistory: asBool(
        j['omitSensitiveInHistory'],
        d.omitSensitiveInHistory,
      ),
      confirmDestructive: asBool(j['confirmDestructive'], d.confirmDestructive),
      onboardingDone: asBool(j['onboardingDone'], d.onboardingDone),
      useCookieJar: asBool(j['useCookieJar'], d.useCookieJar),
      httpVersion: enumByName(
        HttpVersionPref.values,
        j['httpVersion'],
        d.httpVersion,
      ),
      clientCertPath: asString(j['clientCertPath']).trim(),
      clientKeyPath: asString(j['clientKeyPath']).trim(),
      caCertPath: asString(j['caCertPath']).trim(),
      restoreWorkspace: asBool(j['restoreWorkspace'], d.restoreWorkspace),
      checkUpdates: asBool(j['checkUpdates'], d.checkUpdates),
      themeSchedule: asBool(j['themeSchedule'], d.themeSchedule),
      darkFromMinutes: asInt(
        j['darkFromMinutes'],
        d.darkFromMinutes,
      ).clamp(0, 1439),
      darkToMinutes: asInt(j['darkToMinutes'], d.darkToMinutes).clamp(0, 1439),
      skippedVersion: asString(j['skippedVersion']).trim(),
      shortcuts: _parseShortcuts(j['shortcuts']),
    );
  }

  /// Strict parse used for user-initiated imports. Returns an error message
  /// instead of silently accepting garbage.
  static ({AppSettings? settings, String? error}) tryParse(String text) {
    if (text.length > 256 * 1024) {
      return (settings: null, error: 'too_large');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return (settings: null, error: 'not_object');
      final v = asInt(decoded['schemaVersion'], 1);
      if (v > settingsSchemaVersion) {
        return (settings: null, error: 'newer_version');
      }
      return (settings: AppSettings.fromJson(decoded), error: null);
    } on FormatException {
      return (settings: null, error: 'invalid_json');
    }
  }
}

Map<String, String> _parseShortcuts(Object? raw) {
  final m = asMap(raw);
  final out = <String, String>{};
  m.forEach((k, v) {
    if (v is String && v.length <= 40 && k.length <= 40) out[k] = v;
  });
  return out;
}

/// True when the dark theme should be on at [now] under the schedule in [s].
/// The window may cross midnight (for example 19:00 to 07:00). When both
/// times are equal the schedule never turns dark.
bool isDarkBySchedule(AppSettings s, DateTime now) {
  final m = now.hour * 60 + now.minute;
  final from = s.darkFromMinutes;
  final to = s.darkToMinutes;
  if (from == to) return false;
  return from < to ? (m >= from && m < to) : (m >= from || m < to);
}
