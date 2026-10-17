import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(Brightness brightness, {PostBoxColors? tokens}) {
  final c =
      tokens ??
      (brightness == Brightness.dark
          ? PostBoxColors.orangeDark
          : PostBoxColors.orangeLight);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: c.onAccent,
    surface: c.surfaceBase,
    onSurface: c.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surfaceBase,
    dividerColor: c.border,
    extensions: <ThemeExtension<dynamic>>[c],
  );
}
