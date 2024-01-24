// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:graphs/graphs.dart' as graphs;
import 'package:web/helpers.dart';

import '../run_main.dart';
import '../web_utils.dart';
import 'restarter.dart';

@JS(r'$dartRunMain')
external set dartRunMain(JSFunction func);

@JS(r'$dartRunMain')
external JSFunction get dartRunMain;

@JS(r'$requireLoader')
external RequireLoader get requireLoader;

@anonymous
@JS()
@staticInterop
class RequireLoader {}

extension RequireLoaderExtension on RequireLoader {
  external String get digestsPath;

  external JsMap<JSString, JSArray> get moduleParentsGraph;

  external void forceLoadModule(
    JSString moduleId,
    JSFunction callback,
    JSFunction onError,
  );
}

@anonymous
@JS()
@staticInterop
class Sdk {}

@JS(r'$loadModuleConfig')
external Sdk require(String value);

Sdk get sdk => require('dart_sdk');

extension SdkExtension on Sdk {
  JSObject get dart => (this as JSObject)['dart'] as JSObject;
  JSObject get developer => (this as JSObject)['developer'] as JSObject;
  JSObject get extensions => developer['_extensions'] as JSObject;
}

class HotReloadFailedException implements Exception {
  final String _s;

  HotReloadFailedException(this._s);
  @override
  String toString() => "HotReloadFailedException: '$_s'";
}

/// Handles hot restart reloading for use with the require module system.
class RequireRestarter implements Restarter {
  /// The last known digests of all the modules in the application.
  ///
  /// This is updated in place during calls to hotRestart.
  static late Map<String, String> _lastKnownDigests;

  final _moduleOrdering = HashMap<String, int>();
  late SplayTreeSet<String> _dirtyModules;
  var _running = Completer<bool>()..complete(true);

  var count = 0;

  RequireRestarter._() {
    _dirtyModules = SplayTreeSet(_moduleTopologicalCompare);
  }

  @override
  Future<bool> restart({String? runId}) async {
    final dart = sdk.dart;
    final developer = sdk.developer;
    final extensions = sdk.extensions;

    if (extensions
        .callMethod(
          'containsKey'.toJS,
          'ext.flutter.disassemble'.toJS,
        )
        .dartify() as bool) {
      await (developer.callMethod(
        'invokeExtension'.toJS,
        'ext.flutter.disassemble'.toJS,
        '{}'.toJS,
      ) as JSPromise)
          .toDart;
    }

    final newDigests = await _getDigests();
    final modulesToLoad = <String>[];
    for (var moduleId in newDigests.keys) {
      if (!_lastKnownDigests.containsKey(moduleId)) {
        print('Error during script reloading, refreshing the page. \n'
            'Unable to find an existing digest for module: $moduleId.');
        _reloadPage();
      } else if (_lastKnownDigests[moduleId] != newDigests[moduleId]) {
        _lastKnownDigests[moduleId] = newDigests[moduleId]!;
        modulesToLoad.add(moduleId);
      }
    }

    var result = true;
    if (modulesToLoad.isNotEmpty) {
      _updateGraph();
      result = await _reload(modulesToLoad);
    }
    dart.callMethod('hotRestart'.toJS, runId?.toJS);
    runMain();
    return result;
  }

  Iterable<String> _allModules() => requireLoader.moduleParentsGraph.modules;

  Future<Map<String, String>> _getDigests() async {
    final request = await HttpRequest.request(
      requireLoader.digestsPath,
      responseType: 'json',
      method: 'GET',
    );

    final response = request.response.dartify();
    return (response as Map).cast<String, String>();
  }

  Future<void> _initialize() async {
    _lastKnownDigests = await _getDigests();
  }

  List<String> _moduleParents(String module) =>
      requireLoader.moduleParentsGraph.parents(module);

  int _moduleTopologicalCompare(String module1, String module2) {
    var topological = 0;

    final order1 = _moduleOrdering[module1];
    final order2 = _moduleOrdering[module2];

    if (order1 == null || order2 == null) {
      final missing = order1 == null ? module1 : module2;
      throw HotReloadFailedException(
        'Unable to fetch ordering info for module: $missing',
      );
    }

    topological = Comparable.compare(
      _moduleOrdering[module2]!,
      _moduleOrdering[module1]!,
    );

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
    final dart = sdk.dart;

    // As function is async, it can potentially be called second time while
    // first invocation is still running. In this case just mark as dirty and
    // wait until loop from the first call will do the work
    if (!_running.isCompleted) return await _running.future;
    _running = Completer();

    var reloadedModules = 0;
    try {
      _dirtyModules.addAll(modules);
      String? previousModuleId;
      while (_dirtyModules.isNotEmpty) {
        final moduleId = _dirtyModules.first;
        _dirtyModules.remove(moduleId);
        final parentIds = _moduleParents(moduleId);
        // Check if this is the root / bootstrap module.
        if (parentIds.isEmpty) {
          // The bootstrap module is not reloaded but we need to update the
          // $dartRunMain reference to the newly loaded child module.
          final childModule = dart.callMethod<JSObject>(
            'getModuleLibraries'.toJS,
            previousModuleId?.toJS,
          );
          final mainLibrary = childModule.values.first! as JSObject;
          dartRunMain = () {
            mainLibrary.callMethod('main'.toJS);
          }.toJS;
        } else {
          ++reloadedModules;
          await _reloadModule(moduleId);
          parentIds.sort(_moduleTopologicalCompare);
          _dirtyModules.addAll(parentIds);
          previousModuleId = moduleId;
        }
      }
      print('$reloadedModules module(s) were hot-reloaded.');
      _running.complete(true);
    } on HotReloadFailedException catch (e) {
      print('Error during script reloading. Firing full page reload. $e');
      _reloadPage();
      _running.complete(false);
    }
    return _running.future;
  }

  Future<void> _reloadModule(String moduleId) {
    final completer = Completer();
    final stackTrace = StackTrace.current;
    requireLoader.forceLoadModule(
      moduleId.toJS,
      // Removing the argument type in complete()
      // ignore: unnecessary_lambdas
      () {
        completer.complete();
      }.toJS,
      (JsError e) {
        completer.completeError(
          HotReloadFailedException(e.message),
          stackTrace,
        );
      }.toJS,
    );
    return completer.future;
  }

  void _reloadPage() {
    window.location.reload();
  }

  void _updateGraph() {
    final allModules = _allModules();

    final stronglyConnectedComponents =
        graphs.stronglyConnectedComponents(allModules, _moduleParents);
    _moduleOrdering.clear();
    for (var i = 0; i < stronglyConnectedComponents.length; i++) {
      for (var module in stronglyConnectedComponents[i]) {
        _moduleOrdering[module] = i;
      }
    }
  }

  static Future<RequireRestarter> create() async {
    final reloader = RequireRestarter._();
    await reloader._initialize();
    return reloader;
  }
}
