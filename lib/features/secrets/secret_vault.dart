import '../environments/domain/variables.dart';
import '../requests/domain/request_models.dart';
import 'secret_store.dart';

/// Moves secret fields between in-memory models and the [SecretStore].
/// Databases and exports only ever see the non-secret half.
class SecretVault {
  const SecretVault(this.store);

  final SecretStore store;

  bool get isPersistent => store.isPersistent;

  String _reqKey(String requestId, String field) => 'req.$requestId.$field';
  String _varKey(String variableId) => 'var.$variableId';
  String _nodeKey(String ownerId, String field) => 'node.$ownerId.$field';

  /// Auth secrets of a collection or folder (inherited auth).
  Future<void> saveNodeAuth(String ownerId, AuthConfig auth) async {
    for (final e in auth.secretFields().entries) {
      final key = _nodeKey(ownerId, e.key);
      if (e.value.isEmpty) {
        await store.delete(key);
      } else {
        await store.write(key, e.value);
      }
    }
  }

  Future<AuthConfig> loadNodeAuth(String ownerId, AuthConfig auth) async {
    final secrets = <String, String>{};
    for (final k in AuthConfig.secretKeys) {
      final v = await store.read(_nodeKey(ownerId, k));
      if (v != null) secrets[k] = v;
    }
    return auth.withSecrets(secrets);
  }

  Future<void> deleteNodeAuth(String ownerId) async {
    for (final k in AuthConfig.secretKeys) {
      await store.delete(_nodeKey(ownerId, k));
    }
  }

  Future<void> copyNodeAuth(String fromId, String toId) async {
    for (final k in AuthConfig.secretKeys) {
      final v = await store.read(_nodeKey(fromId, k));
      if (v != null) await store.write(_nodeKey(toId, k), v);
    }
  }

  Future<void> saveRequest(RequestModel r) async {
    for (final e in r.auth.secretFields().entries) {
      final key = _reqKey(r.id, e.key);
      if (e.value.isEmpty) {
        await store.delete(key);
      } else {
        await store.write(key, e.value);
      }
    }
  }

  Future<RequestModel> loadRequest(RequestModel r) async {
    final secrets = <String, String>{};
    for (final k in AuthConfig.secretKeys) {
      final v = await store.read(_reqKey(r.id, k));
      if (v != null) secrets[k] = v;
    }
    return r.copyWith(auth: r.auth.withSecrets(secrets));
  }

  Future<void> deleteRequest(String requestId) async {
    for (final k in AuthConfig.secretKeys) {
      await store.delete(_reqKey(requestId, k));
    }
  }

  Future<void> copyRequest(String fromId, String toId) async {
    for (final k in AuthConfig.secretKeys) {
      final v = await store.read(_reqKey(fromId, k));
      if (v != null) await store.write(_reqKey(toId, k), v);
    }
  }

  Future<void> saveVariables(List<Variable> vars) async {
    for (final v in vars) {
      if (v.secret && v.value.isNotEmpty) {
        await store.write(_varKey(v.id), v.value);
      } else {
        await store.delete(_varKey(v.id));
      }
    }
  }

  Future<List<Variable>> loadVariables(List<Variable> vars) async {
    final out = <Variable>[];
    for (final v in vars) {
      if (v.secret) {
        out.add(v.copyWith(value: await store.read(_varKey(v.id)) ?? ''));
      } else {
        out.add(v);
      }
    }
    return out;
  }

  Future<void> deleteVariables(List<Variable> vars) async {
    for (final v in vars) {
      await store.delete(_varKey(v.id));
    }
  }
}
