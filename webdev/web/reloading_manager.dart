// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:graphs/graphs.dart' as graphs;
import 'package:pedantic/pedantic.dart';

import 'module.dart';

class HotReloadFailedException implements Exception {
  HotReloadFailedException(this._s);

  @override
  String toString() => "HotReloadFailedException: '$_s'";
  final String _s;
}

/// Handles reloading order and hooks invocation
class ReloadingManager {
  final Future<Module> Function(String) _reloadModule;
  final Module Function(String) _moduleLibraries;
  final void Function() _reloadPage;
  final List<String> Function(String moduleId) _moduleParents;
  final Iterable<String> Function() _allModules;

  final _moduleOrdering = HashMap<String, int>();
  SplayTreeSet<String> _dirtyModules;
  var _running = Completer<bool>()..complete();

  int moduleTopologicalCompare(String module1, String module2) {
    var topological = 0;

    final order1 = _moduleOrdering[module1];
    final order2 = _moduleOrdering[module2];

    if (order1 == null || order2 == null) {
      var missing = order1 == null ? module1 : module2;
      throw HotReloadFailedException(
          'Unable to fetch ordering info for module: $missing');
    }

    topological =
        Comparable.compare(_moduleOrdering[module2], _moduleOrdering[module1]);

    if (topological == 0) {
      // If modules are in cycle (same strongly connected component) compare their
      // string id, to ensure total ordering for SplayTreeSet uniqueness.
      topological = module1.compareTo(module2);
    }

    return topological;
  }

  void updateGraph() {
    var allModules = _allModules();
    var stronglyConnectedComponents =
        graphs.stronglyConnectedComponents(allModules, _moduleParents);
    _moduleOrdering.clear();
    for (var i = 0; i < stronglyConnectedComponents.length; i++) {
      for (var module in stronglyConnectedComponents[i]) {
        _moduleOrdering[module] = i;
      }
    }
  }

  ReloadingManager(this._reloadModule, this._moduleLibraries, this._reloadPage,
      this._moduleParents, this._allModules) {
    _dirtyModules = SplayTreeSet(moduleTopologicalCompare);
  }

  var count = 0;

  /// Returns `true` if the reload was fully handled, `false` if it failed
  /// explicitly, or `null` for an unhandled reload.
  Future<bool> reload(List<String> modules) async {
    _dirtyModules.addAll(modules);

    // As function is async, it can potentially be called second time while
    // first invocation is still running. In this case just mark as dirty and
    // wait until loop from the first call will do the work
    if (!_running.isCompleted) return await _running.future;
    _running = Completer();

    // We want to schedule some async work for the future but return the
    // `_running` completers future synchronously.
    unawaited(() async {
      var reloadedModules = 0;

      try {
        while (_dirtyModules.isNotEmpty) {
          var moduleId = _dirtyModules.first;
          _dirtyModules.remove(moduleId);
          ++reloadedModules;

          var existing = _moduleLibraries(moduleId);
          var data = existing.onDestroy();

          var newVersion = await _reloadModule(moduleId);
          var success = newVersion.onSelfUpdate(data);
          if (success == true) continue;
          if (success == false) {
            print("Module '$moduleId' is marked as unreloadable. "
                'Firing full page reload.');
            _reloadPage();
            return false;
          }

          var parentIds = _moduleParents(moduleId);
          if (parentIds == null || parentIds.isEmpty) {
            print("Module reloading wasn't handled by any of parents. "
                'Firing full page reload.');
            _reloadPage();
            return false;
          }
          parentIds.sort(moduleTopologicalCompare);

          for (var parentId in parentIds) {
            var parentModule = _moduleLibraries(parentId);
            success = parentModule.onChildUpdate(moduleId, newVersion, data);

            // Found the bootstrap module at the top of the app, return null to
            // indicate an unhandled reload.
            if (parentId.endsWith('.dart.bootstrap')) {
              return null;
            }

            if (success == true) continue;
            if (success == false) {
              print("Module '$moduleId' is marked as unreloadable. "
                  'Firing full page reload.');
              _reloadPage();
              return false;
            }
            _dirtyModules.add(parentId);
          }
        }
        print('$reloadedModules modules were hot-reloaded.');
      } on HotReloadFailedException catch (e) {
        print('Error during script reloading. Firing full page reload. $e');
        _reloadPage();
        return false;
      }
      return true;
    }()
        .then(_running.complete)
        .catchError(_running.completeError));

    return _running.future;
  }
}
