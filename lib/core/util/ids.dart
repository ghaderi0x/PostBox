import 'dart:math';

final Random _rng = Random.secure();

/// 128-bit random identifier as 32 hex characters.
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
