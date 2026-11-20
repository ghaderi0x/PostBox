import 'dart:io';

/// True on Windows, Linux and macOS. Phones and tablets (Android) are false.
/// Desktop-only UI (keyboard shortcut guide, installer updates, compact
/// toasts) is gated on this so the phone UI stays as it is.
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

bool get isAndroidPlatform => Platform.isAndroid;
