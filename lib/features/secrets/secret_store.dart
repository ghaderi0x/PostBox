import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/util/app_log.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clearAll();

  /// False when the platform keystore is unavailable and values only live in
  /// memory for this session (for example Linux without a keyring service).
  bool get isPersistent;
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> _data = <String, String>{};

  @override
  bool get isPersistent => false;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clearAll() async => _data.clear();
}

/// Uses the platform keystore through flutter_secure_storage. If the keystore
/// fails (missing libsecret/keyring on Linux, locked keyring), it degrades to
/// an in-memory store and reports [isPersistent] == false instead of crashing.
class GracefulSecretStore implements SecretStore {
  GracefulSecretStore({FlutterSecureStorage? storage, AppLog? log})
    : _storage = storage ?? const FlutterSecureStorage(),
      _log = log;

  static const String _prefix = 'postbox.';

  final FlutterSecureStorage _storage;
  final AppLog? _log;
  final MemorySecretStore _fallback = MemorySecretStore();
  bool _broken = false;

  @override
  bool get isPersistent => !_broken;

  void _markBroken(Object e) {
    if (!_broken) {
      _broken = true;
      _log?.warn(
        'Secure storage unavailable, using memory only: ${e.runtimeType}',
      );
    }
  }

  @override
  Future<String?> read(String key) async {
    if (!_broken) {
      try {
        final v = await _storage.read(key: '$_prefix$key');
        if (v != null) return v;
      } on Exception catch (e) {
        _markBroken(e);
      }
    }
    return _fallback.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_broken) {
      try {
        await _storage.write(key: '$_prefix$key', value: value);
        return;
      } on Exception catch (e) {
        _markBroken(e);
      }
    }
    await _fallback.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (!_broken) {
      try {
        await _storage.delete(key: '$_prefix$key');
      } on Exception catch (e) {
        _markBroken(e);
      }
    }
    await _fallback.delete(key);
  }

  @override
  Future<void> clearAll() async {
    if (!_broken) {
      try {
        final all = await _storage.readAll();
        for (final k in all.keys.where((k) => k.startsWith(_prefix))) {
          await _storage.delete(key: k);
        }
      } on Exception catch (e) {
        _markBroken(e);
      }
    }
    await _fallback.clearAll();
  }
}
