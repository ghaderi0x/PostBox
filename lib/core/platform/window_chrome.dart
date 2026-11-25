import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colours the native Windows title bar so it matches the in-app header.
///
/// Needs the runner patch from tool/apply_windows_titlebar.sh. If the patch
/// is missing, or on other systems, every call is a no-op. Windows 11 colours
/// the bar; Windows 10 only switches between its light and dark title bar.
class WindowChrome {
  static const MethodChannel _channel = MethodChannel('postbox/window');

  /// Windows COLORREF is 0x00BBGGRR.
  static int _colorRef(Color c) {
    final v = c.toARGB32();
    return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF);
  }

  static Future<void> setTitleBar({
    required Color background,
    required Color text,
    required Color border,
    required bool dark,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('setTitleBar', <String, Object>{
        'background': _colorRef(background),
        'text': _colorRef(text),
        'border': _colorRef(border),
        'dark': dark,
      });
    } on MissingPluginException {
      // Runner not patched: keep the default title bar.
    } on PlatformException {
      // Not supported by this Windows version.
    }
  }
}
