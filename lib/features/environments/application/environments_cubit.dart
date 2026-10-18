import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/ids.dart';
import '../../secrets/secret_vault.dart';
import '../data/environment_repository.dart';
import '../domain/variables.dart';

class EnvironmentsState {
  const EnvironmentsState({
    this.environments = const <Environment>[],
    this.activeId,
    this.globals = const <Variable>[],
    this.secretsPersistent = true,
  });

  final List<Environment> environments;
  final String? activeId;
  final List<Variable> globals;
  final bool secretsPersistent;

  Environment? get active {
    for (final e in environments) {
      if (e.id == activeId) return e;
    }
    return null;
  }
}

class EnvironmentsCubit extends Cubit<EnvironmentsState> {
  EnvironmentsCubit(this._repo, this._vault) : super(const EnvironmentsState());

  final EnvironmentRepository _repo;
  final SecretVault _vault;

  Future<void> load() async {
    final envs = <Environment>[];
    for (final e in _repo.list()) {
      envs.add(e.copyWith(variables: await _vault.loadVariables(e.variables)));
    }
    final globals = await _vault.loadVariables(_repo.globals());
    var active = _repo.activeId();
    if (active != null && !envs.any((e) => e.id == active)) active = null;
    emit(EnvironmentsState(
      environments: envs,
      activeId: active,
      globals: globals,
      secretsPersistent: _vault.isPersistent,
    ));
  }

  Future<Environment> create(String name) async {
    final env = Environment(id: newId(), name: name.trim().isEmpty ? 'Environment' : name.trim());
    await save(env);
    return env;
  }

  Future<void> save(Environment e) async {
    await _vault.saveVariables(e.variables);
    _repo.save(e);
    final list = List<Environment>.of(state.environments);
    final i = list.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      list[i] = e;
    } else {
      list.add(e);
    }
    emit(EnvironmentsState(
      environments: list,
      activeId: state.activeId,
      globals: state.globals,
      secretsPersistent: _vault.isPersistent,
    ));
  }

  Future<void> delete(String id) async {
    final env = state.environments.where((e) => e.id == id).firstOrNull;
    if (env != null) await _vault.deleteVariables(env.variables);
    _repo.delete(id);
    emit(EnvironmentsState(
      environments: state.environments.where((e) => e.id != id).toList(),
      activeId: state.activeId == id ? null : state.activeId,
      globals: state.globals,
      secretsPersistent: _vault.isPersistent,
    ));
  }

  Future<void> setActive(String? id) async {
    _repo.setActive(id);
    emit(EnvironmentsState(
      environments: state.environments,
      activeId: id,
      globals: state.globals,
      secretsPersistent: _vault.isPersistent,
    ));
  }

  Future<void> saveGlobals(List<Variable> vars) async {
    await _vault.saveVariables(vars);
    _repo.saveGlobals(vars);
    emit(EnvironmentsState(
      environments: state.environments,
      activeId: state.activeId,
      globals: vars,
      secretsPersistent: _vault.isPersistent,
    ));
  }

  /// Stores values extracted by request chaining as ordinary variables in the
  /// active environment, or in globals when none is active.
  Future<void> setExtracted(Map<String, String> values) async {
    if (values.isEmpty) return;
    List<Variable> upsert(List<Variable> src) {
      final out = List<Variable>.of(src);
      values.forEach((k, v) {
        final i = out.indexWhere((x) => x.key == k);
        if (i >= 0) {
          out[i] = out[i].copyWith(value: v);
        } else {
          out.add(Variable(id: newId(), key: k, value: v));
        }
      });
      return out;
    }

    final env = state.active;
    if (env != null) {
      await save(env.copyWith(variables: upsert(env.variables)));
    } else {
      await saveGlobals(upsert(state.globals));
    }
  }
}
