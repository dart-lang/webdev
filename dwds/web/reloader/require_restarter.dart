// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library require_reloading_manager;

import 'dart:async';
import 'dart:collection';
import 'dart:html';
import 'dart:js_util';

import 'package:graphs/graphs.dart' as graphs;
import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:path/path.dart' as p;
import 'package:pedantic/pedantic.dart';

import '../promise.dart';
import 'restarter.dart';

/// The last known digests of all the modules in the application.
///
/// This is updated in place during calls to hotRestart.
Map<String, String> _lastKnownDigests;

@JS(r'$dartLoader')
external DartLoader get dartLoader;

@JS(r'$loadModuleConfig')
external Object Function(String module) get require;

List<K> keys<K, V>(JsMap<K, V> map) {
  return List.from(_jsArrayFrom(map.keys()));
}

@JS('Array.from')
external List _jsArrayFrom(Object any);

@anonymous
@JS()
class DartLoader {
  @JS()
  external String get appDigests;

  @JS()
  external JsMap<String, List<String>> get moduleParentsGraph;

  @JS()
  external JsMap<String, String> get urlToModuleId;

  @JS()
  external void forceLoadModule(String moduleId, void Function() callback,
      void Function(JsError e) onError);
}

class HotReloadFailedException implements Exception {
  final String _s;

  HotReloadFailedException(this._s);
  @override
  String toString() => "HotReloadFailedException: '$_s'";
}

@JS('Error')
abstract class JsError {
  @JS()
  external String get message;

  @JS()
  external String get stack;
}

@JS('Map')
abstract class JsMap<K, V> {
  @JS()
  external V get(K key);

  @JS()
  external Object keys();
}

/// Handles hot restart reloading for use with the require module system.
class RequireRestarter implements Restarter {
  final _moduleOrdering = HashMap<String, int>();
  SplayTreeSet<String> _dirtyModules;
  var _running = Completer<bool>()..complete();

  var count = 0;

  RequireRestarter._() {
    _dirtyModules = SplayTreeSet(_moduleTopologicalCompare);
  }

  @override
  Future<bool> restart() async {
    var developer = getProperty(require('dart_sdk'), 'developer');
    if (callMethod(getProperty(developer, '_extensions'), 'containsKey',
        ['ext.flutter.disassemble']) as bool) {
      await toFuture(callMethod(
              developer, 'invokeExtension', ['ext.flutter.disassemble', '{}'])
          as Promise<void>);
    }

    var newDigests = await _getDigests();
    var modulesToLoad = <String>[];
    for (var jsPath in newDigests.keys) {
      if (!_lastKnownDigests.containsKey(jsPath) ||
          _lastKnownDigests[jsPath] != newDigests[jsPath]) {
        _lastKnownDigests[jsPath] = newDigests[jsPath];
        var parts = p.url.split(jsPath);
        // We serve top level dirs, so this strips the top level dir from all
        // but `packages` paths.
        var servePath =
            parts.first == 'packages' ? jsPath : p.url.joinAll(parts.skip(1));
        var jsUri = '${window.location.origin}/$servePath';
        var moduleName = dartLoader.urlToModuleId.get(jsUri);
        if (moduleName == null) {
          print('Error during script reloading, refreshing the page. \n'
              'Unable to find an existing module for script $jsUri.');
          _reloadPage();
          return false;
        }
        modulesToLoad.add(moduleName);
      }
    }

    if (modulesToLoad.isNotEmpty) {
      _updateGraph();
      var result = await _reload(modulesToLoad);
      if (result == null) {
        callMethod(getProperty(require('dart_sdk'), 'dart'), 'hotRestart', []);
        result = true;
      }
      return result;
    }

    callMethod(getProperty(require('dart_sdk'), 'dart'), 'hotRestart', []);
    return true;
  }

  List<String> _allModules() => keys(dartLoader.moduleParentsGraph);

  Future<Map<String, String>> _getDigests() async {
    var request = await HttpRequest.request(dartLoader.appDigests,
        responseType: 'json', method: 'GET');
    return (request.response as Map).cast<String, String>();
  }

  Future<void> _initialize() async {
    _lastKnownDigests = await _getDigests();
  }

  List<String> _moduleParents(String module) =>
      dartLoader.moduleParentsGraph.get(module)?.cast();

  int _moduleTopologicalCompare(String module1, String module2) {
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
      // If modules are in cycle (same strongly connected component) compare
      // their string id, to ensure total ordering for SplayTreeSet uniqueness.
      topological = module1.compareTo(module2);
    }

    return topological;
  }

  /// Returns `true` if the reload was fully handled, `false` if it failed
  /// explicitly, or `null` for an unhandled reload.
  Future<bool> _reload(List<String> modules) async {
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
          await _reloadModule(moduleId);
          var parentIds = _moduleParents(moduleId);
          if (parentIds == null || parentIds.isEmpty) {
            print("Module reloading wasn't handled by any of parents. "
                'Firing full page reload.');
            _reloadPage();
          }
          parentIds.sort(_moduleTopologicalCompare);
          _dirtyModules
              .addAll(parentIds.where((id) => !id.endsWith('.dart.bootstrap')));
        }
        print('$reloadedModules module(s) were hot-reloaded.');
      } on HotReloadFailedException catch (e) {
        print('Error during script reloading. Firing full page reload. $e');
        _reloadPage();
      }
    }()
        .then(_running.complete)
        .catchError(_running.completeError));

    return _running.future;
  }

  Future<void> _reloadModule(String moduleId) {
    var completer = Completer();
    var stackTrace = StackTrace.current;
    dartLoader.forceLoadModule(moduleId, allowInterop(() {
      completer.complete();
    }),
        allowInterop((e) => completer.completeError(
            HotReloadFailedException(e.message), stackTrace)));
    return completer.future;
  }

  void _reloadPage() {
    window.location.reload();
  }

  void _updateGraph() {
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

  static Future<RequireRestarter> create() async {
    var reloader = RequireRestarter._();
    await reloader._initialize();
    return reloader;
  }
}
