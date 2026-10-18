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
    this.themeMode = AppThemeMode.system,
    this.themePreset = ThemePreset.orange,
    this.accentOverride,
    this.surfaceStyle = SurfaceStyle.raised,
    this.density = UiDensity.comfortable,
    this.fontScale = 1.0,
    this.reducedMotion = false,
    this.language = AppLanguage.system,
    this.persianDigits = false,
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
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      themePreset: themePreset ?? this.themePreset,
      accentOverride: clearAccent ? null : (accentOverride ?? this.accentOverride),
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
    );
  }

  /// [redactSensitive] masks values of sensitive default headers, which is the
  /// default for settings exports.
  Map<String, dynamic> toJson({bool redactSensitive = false}) {
    final headers = defaultHeaders
        .map((h) => redactSensitive && Redactor.isSensitiveHeader(h.key)
            ? h.copyWith(value: Redactor.mask).toJson()
            : h.toJson())
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
    };
  }

  String toJsonString({bool redactSensitive = false}) =>
      const JsonEncoder.withIndent('  ')
          .convert(toJson(redactSensitive: redactSensitive));

  /// Migrates older schema versions to the current one. There is only one
  /// version so far; this is where future steps are chained.
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final v = asInt(out['schemaVersion'], 0);
    if (v < 1) {
      out['schemaVersion'] = 1;
    }
    return out;
  }

  /// Lenient: never throws, clamps ranges, ignores unknown keys.
  factory AppSettings.fromJson(Object? raw) {
    const d = AppSettings();
    final j = migrate(asMap(raw));
    final method = asString(j['defaultMethod'], d.defaultMethod).trim().toUpperCase();
    final proxy = asString(j['proxy']).trim();
    final tab = asInt(j['editorTabSize'], d.editorTabSize);
    final accent = j['accentOverride'];
    final headers = KeyValue.listFromJson(j['defaultHeaders'])
        .where((h) => h.key.trim().isNotEmpty)
        .toList();
    return AppSettings(
      themeMode: enumByName(AppThemeMode.values, j['themeMode'], d.themeMode),
      themePreset: enumByName(ThemePreset.values, j['themePreset'], d.themePreset),
      accentOverride: accent is int ? accent : null,
      surfaceStyle: enumByName(SurfaceStyle.values, j['surfaceStyle'], d.surfaceStyle),
      density: enumByName(UiDensity.values, j['density'], d.density),
      fontScale: clampDouble(asDouble(j['fontScale'], d.fontScale), 0.8, 1.6),
      reducedMotion: asBool(j['reducedMotion'], d.reducedMotion),
      language: enumByName(AppLanguage.values, j['language'], d.language),
      persianDigits: asBool(j['persianDigits'], d.persianDigits),
      jalaliDates: asBool(j['jalaliDates'], d.jalaliDates),
      defaultMethod: method.isEmpty ? d.defaultMethod : method,
      timeoutSeconds: clampInt(asInt(j['timeoutSeconds'], d.timeoutSeconds), 1, 600),
      redirectPolicy: enumByName(RedirectPolicy.values, j['redirectPolicy'], d.redirectPolicy),
      maxRedirects: clampInt(asInt(j['maxRedirects'], d.maxRedirects), 0, 30),
      proxy: isValidProxy(proxy) ? proxy : '',
      allowInvalidCertificates:
          asBool(j['allowInvalidCertificates'], d.allowInvalidCertificates),
      defaultHeaders: headers,
      maxResponseMb: clampInt(asInt(j['maxResponseMb'], d.maxResponseMb), 1, 200),
      maxRequestMb: clampInt(asInt(j['maxRequestMb'], d.maxRequestMb), 1, 100),
      editorWordWrap: asBool(j['editorWordWrap'], d.editorWordWrap),
      editorLineNumbers: asBool(j['editorLineNumbers'], d.editorLineNumbers),
      editorFontSize: clampDouble(asDouble(j['editorFontSize'], d.editorFontSize), 10, 24),
      editorTabSize: tab == 4 ? 4 : 2,
      editorAutoClose: asBool(j['editorAutoClose'], d.editorAutoClose),
      editorHighlightVariables:
          asBool(j['editorHighlightVariables'], d.editorHighlightVariables),
      persistHistory: asBool(j['persistHistory'], d.persistHistory),
      historyRetentionDays:
          clampInt(asInt(j['historyRetentionDays'], d.historyRetentionDays), 0, 3650),
      historyMaxEntries:
          clampInt(asInt(j['historyMaxEntries'], d.historyMaxEntries), 10, 10000),
      omitSensitiveInHistory:
          asBool(j['omitSensitiveInHistory'], d.omitSensitiveInHistory),
      confirmDestructive: asBool(j['confirmDestructive'], d.confirmDestructive),
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
