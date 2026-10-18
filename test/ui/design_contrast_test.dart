import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/design/presets.dart';
import 'package:postbox/core/design/tokens.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final preset in ThemePreset.values) {
    for (final b in Brightness.values) {
      test('${preset.name} ${b.name}: text and accent contrast', () {
        final c = buildColors(preset, b);
        final min = preset == ThemePreset.highContrast ? 7.0 : 4.5;
        expect(contrast(c.textPrimary, c.surfaceBase), greaterThanOrEqualTo(min), reason: 'text/base');
        expect(contrast(c.textPrimary, c.surfaceRaised), greaterThanOrEqualTo(min), reason: 'text/raised');
        expect(contrast(c.textSecondary, c.surfaceBase), greaterThanOrEqualTo(4.5), reason: 'secondary/base');
        expect(contrast(c.textSecondary, c.surfaceRaised), greaterThanOrEqualTo(4.5), reason: 'secondary/raised');
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5), reason: 'onAccent/accent');
        expect(contrast(c.accent, c.surfaceBase), greaterThanOrEqualTo(3.0), reason: 'accent/base');
      });

      test('${preset.name} ${b.name}: semantic and syntax colors are readable', () {
        final c = buildColors(preset, b);
        final fg = <String, Color>{
          'success': c.success,
          'warning': c.warning,
          'danger': c.danger,
          'GET': c.methodGet,
          'POST': c.methodPost,
          'PUT': c.methodPut,
          'PATCH': c.methodPatch,
          'DELETE': c.methodDelete,
          'key': c.synKey,
          'string': c.synString,
          'number': c.synNumber,
          'literal': c.synLiteral,
          'punct': c.synPunct,
        };
        fg.forEach((name, color) {
          expect(contrast(color, c.surfaceBase), greaterThanOrEqualTo(4.5), reason: '$name on base');
          expect(contrast(color, c.surfaceRaised), greaterThanOrEqualTo(4.5), reason: '$name on raised');
        });
      });
    }
  }

  test('flat surface style keeps text readable', () {
    for (final preset in ThemePreset.values) {
      final c = buildColors(preset, Brightness.light, surface: SurfaceStyle.flat);
      expect(c.surfaceRaised, c.surfaceBase);
      expect(contrast(c.textPrimary, c.surfaceRaised), greaterThanOrEqualTo(4.5));
    }
  });

  test('custom accent picks a readable foreground', () {
    for (final a in kAccentSwatches) {
      final c = buildColors(ThemePreset.orange, Brightness.light, accentOverride: a);
      expect(c.accent, Color(a));
      expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5), reason: a.toRadixString(16));
    }
    expect(onColorFor(const Color(0xFFFFFF00)), const Color(0xFF0A0A0A));
    expect(onColorFor(const Color(0xFF000033)), const Color(0xFFFFFFFF));
  });
}
