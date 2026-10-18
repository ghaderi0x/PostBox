import 'package:flutter/material.dart';

import '../../features/settings/domain/app_settings.dart';
import 'presets.dart';
import 'tokens.dart';

const String kUiFont = 'Inter';
const String kPersianFont = 'Vazirmatn';
const String kMonoFont = 'JetBrainsMono';
const List<String> kMonoFallback = <String>[
  kPersianFont,
  'Consolas',
  'Menlo',
  'monospace',
];

ThemeData buildTheme({
  required Brightness brightness,
  required AppSettings settings,
  required bool persianUi,
}) {
  final c = buildColors(
    settings.themePreset,
    brightness,
    accentOverride: settings.accentOverride,
    surface: settings.surfaceStyle,
  );
  final family = persianUi ? kPersianFont : kUiFont;
  final fallback = persianUi ? <String>[kUiFont] : <String>[kPersianFont];

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: brightness == Brightness.dark ? const Color(0xFF1A0505) : const Color(0xFFFFFFFF),
    surface: c.surfaceBase,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerLowest: c.surfaceBase,
    surfaceContainerLow: c.surfaceBase,
    surfaceContainer: c.surfaceRaised,
    surfaceContainerHigh: c.surfaceRaised,
    surfaceContainerHighest: c.surfaceRaised,
  );

  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final textTheme = base.textTheme.apply(
    bodyColor: c.textPrimary,
    displayColor: c.textPrimary,
    fontFamily: family,
    fontFamilyFallback: fallback,
  );

  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: c.border),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surfaceBase,
    canvasColor: c.surfaceBase,
    dividerColor: c.border,
    fontFamily: family,
    fontFamilyFallback: fallback,
    textTheme: textTheme,
    visualDensity: settings.density == UiDensity.compact
        ? VisualDensity.compact
        : VisualDensity.standard,
    splashFactory: settings.reducedMotion ? NoSplash.splashFactory : null,
    pageTransitionsTheme: settings.reducedMotion
        ? const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: _NoTransitions(),
            TargetPlatform.windows: _NoTransitions(),
            TargetPlatform.linux: _NoTransitions(),
          })
        : null,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      errorBorder: outline.copyWith(borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder:
          outline.copyWith(borderSide: BorderSide(color: c.danger, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: WidgetStateProperty.all(false),
      thickness: WidgetStateProperty.all(6),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: c.textPrimary,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: TextStyle(color: c.surfaceBase, fontSize: 12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surfaceBase,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    extensions: <ThemeExtension<dynamic>>[
      PostBoxTheme(
        colors: c,
        codeFontSize: settings.editorFontSize,
        reducedMotion: settings.reducedMotion,
      ),
    ],
  );
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
