import 'package:flutter/material.dart';

import '../../features/settings/domain/app_settings.dart';
import 'tokens.dart';

class _Neutrals {
  const _Neutrals(
    this.base,
    this.raised,
    this.border,
    this.text,
    this.text2,
    this.accent,
    this.onAccent,
  );
  final int base;
  final int raised;
  final int border;
  final int text;
  final int text2;
  final int accent;
  final int onAccent;
}

/// [light, dark] neutrals per preset. Contrast ratios (text/surface >= 4.5,
/// onAccent/accent >= 4.5) were computed when the table was written; see
/// test/design_contrast_test.dart which re-checks them.
const Map<ThemePreset, List<_Neutrals>> _presets = <ThemePreset, List<_Neutrals>>{
  ThemePreset.orange: <_Neutrals>[
    _Neutrals(0xFFFAF8F6, 0xFFFFFFFF, 0xFFE6E0DA, 0xFF1F1B17, 0xFF6B625A, 0xFFC2410C, 0xFFFFFFFF),
    _Neutrals(0xFF16130F, 0xFF211D18, 0xFF3A342D, 0xFFF3EEE9, 0xFFA89E94, 0xFFFF8A3D, 0xFF1A0E05),
  ],
  ThemePreset.midnight: <_Neutrals>[
    _Neutrals(0xFFF4F6FB, 0xFFFFFFFF, 0xFFDCE1EE, 0xFF141A2A, 0xFF566079, 0xFF2F5BD8, 0xFFFFFFFF),
    _Neutrals(0xFF0E1420, 0xFF151C2B, 0xFF26314A, 0xFFE6EAF4, 0xFF9AA6C0, 0xFF6D9BFF, 0xFF0A1020),
  ],
  ThemePreset.arctic: <_Neutrals>[
    _Neutrals(0xFFF3F8FB, 0xFFFFFFFF, 0xFFD5E3EC, 0xFF0F2230, 0xFF4D6676, 0xFF0A759A, 0xFFFFFFFF),
    _Neutrals(0xFF0D1A22, 0xFF14252F, 0xFF244050, 0xFFE4F1F8, 0xFF93B0C0, 0xFF4CC2EA, 0xFF06141C),
  ],
  ThemePreset.emerald: <_Neutrals>[
    _Neutrals(0xFFF4F9F6, 0xFFFFFFFF, 0xFFD6E6DC, 0xFF10241A, 0xFF4B6657, 0xFF0B7A50, 0xFFFFFFFF),
    _Neutrals(0xFF0E1A14, 0xFF15261C, 0xFF25402F, 0xFFE3F2E9, 0xFF94B3A1, 0xFF3DD598, 0xFF06180F),
  ],
  ThemePreset.violet: <_Neutrals>[
    _Neutrals(0xFFF8F6FC, 0xFFFFFFFF, 0xFFE3DCF0, 0xFF1C1630, 0xFF5F567A, 0xFF6D3FD0, 0xFFFFFFFF),
    _Neutrals(0xFF14101F, 0xFF1C172B, 0xFF372E52, 0xFFEEE9FA, 0xFFA79EC4, 0xFFA78BFA, 0xFF120A26),
  ],
  ThemePreset.highContrast: <_Neutrals>[
    _Neutrals(0xFFFFFFFF, 0xFFFFFFFF, 0xFF000000, 0xFF000000, 0xFF1A1A1A, 0xFF0033CC, 0xFFFFFFFF),
    _Neutrals(0xFF000000, 0xFF000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFE6E6E6, 0xFFFFD400, 0xFF000000),
  ],
};

/// Accent swatches offered in settings besides the custom picker.
const List<int> kAccentSwatches = <int>[
  0xFFC2410C,
  0xFF2F5BD8,
  0xFF0A759A,
  0xFF0B7A50,
  0xFF6D3FD0,
  0xFFB4236C,
];

/// Dark presets look best as dark; Midnight is dark-first in `system` mode
/// only through the brightness the platform asks for, like every other preset.
Color onColorFor(Color c) {
  final l = c.computeLuminance();
  final white = 1.05 / (l + 0.05);
  final black = (l + 0.05) / 0.053;
  return white >= black ? const Color(0xFFFFFFFF) : const Color(0xFF0A0A0A);
}

PostBoxColors buildColors(
  ThemePreset preset,
  Brightness brightness, {
  int? accentOverride,
  SurfaceStyle surface = SurfaceStyle.raised,
}) {
  final dark = brightness == Brightness.dark;
  final n = _presets[preset]![dark ? 1 : 0];
  final accent = Color(accentOverride ?? n.accent);
  final onAccent = accentOverride != null ? onColorFor(accent) : Color(n.onAccent);
  final base = Color(n.base);
  var raised = Color(n.raised);
  var border = Color(n.border);
  if (surface == SurfaceStyle.flat && preset != ThemePreset.highContrast) {
    raised = base;
    border = Color.alphaBlend(border.withAlpha(110), base);
  }
  return PostBoxColors(
    surfaceBase: base,
    surfaceRaised: raised,
    border: border,
    textPrimary: Color(n.text),
    textSecondary: Color(n.text2),
    accent: accent,
    onAccent: onAccent,
    success: Color(dark ? 0xFF4CC38A : 0xFF1B7F4B),
    warning: Color(dark ? 0xFFE3B341 : 0xFF8A5A00),
    danger: Color(dark ? 0xFFFF6B6B : 0xFFC62828),
    methodGet: Color(dark ? 0xFF4CC38A : 0xFF1B7F4B),
    methodPost: Color(dark ? 0xFFFFA94D : 0xFFB45309),
    methodPut: Color(dark ? 0xFF6EA8FE : 0xFF1D5FBF),
    methodPatch: Color(dark ? 0xFFB794F6 : 0xFF6D3FC4),
    methodDelete: Color(dark ? 0xFFFF6B6B : 0xFFC62828),
    synKey: Color(dark ? 0xFF7AB0FF : 0xFF1D4ED8),
    synString: Color(dark ? 0xFF7EE2A8 : 0xFF0B6B3A),
    synNumber: Color(dark ? 0xFFFFB86B : 0xFF9A4A00),
    synLiteral: Color(dark ? 0xFFC4A7FF : 0xFF7C2DD6),
    synPunct: Color(dark ? 0xFF9AA3B2 : 0xFF5B6270),
    synVariable: accent,
    synError: Color(dark ? 0xFFFF6B6B : 0xFFC62828),
  );
}
