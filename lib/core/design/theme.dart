import 'package:flutter/material.dart';

import '../../features/settings/domain/app_settings.dart';
import 'presets.dart';
import 'shapes.dart';
import 'tokens.dart';

const String kUiFont = 'Inter';
const String kPersianFont = 'Vazirmatn';
const String kMonoFont = 'JetBrainsMono';

/// Contains only the ten ASCII digits, drawn with Persian shapes (derived
/// from Vazirmatn). Placed first in the font list when Persian digits are on,
/// so every number in normal UI text shows Persian digits while all other
/// characters fall through to the UI font. Code and URLs keep Latin digits.
const String kDigitsFont = 'PostBoxDigits';
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
  final baseFamily = persianUi ? kPersianFont : kUiFont;
  final baseFallback = persianUi ? <String>[kUiFont] : <String>[kPersianFont];
  final family = settings.persianDigits ? kDigitsFont : baseFamily;
  final fallback = settings.persianDigits
      ? <String>[baseFamily, ...baseFallback]
      : baseFallback;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: brightness == Brightness.dark
        ? const Color(0xFF1A0505)
        : const Color(0xFFFFFFFF),
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

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.md),
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
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
        ? const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: _NoTransitions(),
              TargetPlatform.windows: _NoTransitions(),
              TargetPlatform.linux: _NoTransitions(),
            },
          )
        : null,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      errorBorder: outline.copyWith(borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: c.danger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: const Size(0, 44),
        side: BorderSide(color: c.border),
        foregroundColor: c.textPrimary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: c.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: c.border)),
      side: BorderSide(color: c.border),
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
  ) => child;
}
