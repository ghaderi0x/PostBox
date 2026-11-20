import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Text or file content another Android app shared with PostBox.
class SharedContent {
  const SharedContent({required this.text, this.name});
  final String text;

  /// File name or subject, when the sender gave one.
  final String? name;
}

/// Receives "Share to PostBox" and "Open with" content on Android through the
/// channel implemented in android_overlay/MainActivity.kt. On other platforms
/// it does nothing. The content is only offered to the import page, which
/// shows a preview; nothing is imported or executed automatically.
class ShareIntentService {
  ShareIntentService();

  static const MethodChannel _channel = MethodChannel(
    'com.uniqueone.postbox/share',
  );

  final StreamController<SharedContent> _controller =
      StreamController<SharedContent>.broadcast();

  Stream<SharedContent> get stream => _controller.stream;

  /// Returns the content the app was launched with, if any, and starts
  /// listening for content shared while it is running.
  Future<SharedContent?> init() async {
    if (!Platform.isAndroid) return null;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare') {
        final c = _parse(call.arguments);
        if (c != null) _controller.add(c);
      }
      return null;
    });
    try {
      return _parse(await _channel.invokeMethod<Object?>('getInitialShare'));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  SharedContent? _parse(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final name = raw['name'];
    return SharedContent(text: text, name: name is String ? name : null);
  }

  void dispose() => _controller.close();
}
