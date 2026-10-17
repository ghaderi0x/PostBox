import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/design/theme.dart';
import 'package:postbox/core/design/tokens.dart';

void main() {
  test('light and dark themes expose PostBox tokens', () {
    for (final b in Brightness.values) {
      final t = buildTheme(b);
      expect(t.extension<PostBoxColors>(), isNotNull);
      expect(t.brightness, b);
    }
  });
}
