import 'package:flutter/material.dart';

import '../util/json_util.dart';

/// Corner radii used across the app. Larger radii follow the soft, rounded look.
class Radii {
  const Radii._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 40;
}

/// Soft drop shadow, stronger in dark mode where it reads as depth.
List<BoxShadow> softShadow(BuildContext context, {double strength = 1}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final alpha = clampInt(((dark ? 90 : 24) * strength).round(), 0, 255);
  return <BoxShadow>[
    BoxShadow(
      color: Colors.black.withAlpha(alpha),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
