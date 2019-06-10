// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library hot_reload_client;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:build_daemon/data/build_status.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:path/path.dart' as p;
import 'package:sse/client/sse_client.dart';
import 'package:uuid/uuid.dart';
import 'package:webdev/src/serve/data/connect_request.dart';
import 'package:webdev/src/serve/data/devtools_request.dart';
import 'package:webdev/src/serve/data/isolate_events.dart';
import 'package:webdev/src/serve/data/run_request.dart';
import 'package:webdev/src/serve/data/serializers.dart';

import 'module.dart';
import 'promise.dart';
import 'reloading_manager.dart';

// GENERATE:
// pub run build_runner build web
Future<void> main() async {
  // Set the unique id for this instance of the app.
  // Test apps may already have this set.
  dartAppInstanceId ??= Uuid().v1();

  var currentDigests = await _getDigests();

  var manager = ReloadingManager(
      _reloadModule,
      _moduleLibraries,
      _reloadPage,
      (module) => dartLoader.moduleParentsGraph.get(module)?.cast(),
      () => keys(dartLoader.moduleParentsGraph));

  var client = SseClient(r'/$sseHandler');

  hotRestartJs = allowInterop(() {
    return toPromise(hotRestart(currentDigests, manager, client));
  });

  launchDevToolsJs = allowInterop(() {
    if (!_isChrome) {
      window.alert('Dart DevTools is only supported on Chrome');
      return;
    }
    client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
      ..appId = dartAppId
      ..instanceId = dartAppInstanceId))));
  });

  client.stream.listen((serialized) async {
    var event = serializers.deserialize(jsonDecode(serialized));
    if (event is DefaultBuildResult) {
      if (reloadConfiguration == 'ReloadConfiguration.liveReload') {
        window.location.reload();
      } else if (reloadConfiguration == 'ReloadConfiguration.hotRestart') {
        await hotRestart(currentDigests, manager, client);
      } else if (reloadConfiguration == 'ReloadConfiguration.hotReload') {
        print('Hot reload is currently unsupported. Ignoring change.');
      }
    } else if (event is DevToolsResponse) {
      if (!event.success) {
        window.alert('DevTools failed to open with: ${event.error}');
      }
    } else if (event is RunRequest) {
      runMain();
    }
  });

  window.onKeyDown.listen((e) {
    if (const [
          'd',
          'D',
          '∂', // alt-d output on Mac
          'Î', // shift-alt-D output on Mac
        ].contains(e.key) &&
        e.altKey &&
        !e.ctrlKey &&
        !e.metaKey) {
      e.preventDefault();
      launchDevToolsJs();
    }
  });

  if (_isChrome) {
    // Wait for the connection to be estabilished before sending the AppId.
    await client.onOpen.first;
    client.sink.add(jsonEncode(serializers.serialize(ConnectRequest((b) => b
      ..appId = dartAppId
      ..instanceId = dartAppInstanceId))));
  } else {
    // If not chrome we just invoke main, devtools aren't supported.
    runMain();
  }
}

/// Attemps to perform a hot restart, and returns whether it was successful or
/// not.
Future<bool> hotRestart(Map<String, String> currentDigests,
    ReloadingManager manager, SseClient sseClient) async {
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
    if (!currentDigests.containsKey(jsPath) ||
        currentDigests[jsPath] != newDigests[jsPath]) {
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
  currentDigests = newDigests;

  // Notify webdev that the isolate is about to exit.
  sseClient.sink.add(jsonEncode(serializers.serialize(IsolateExit((b) => b
    ..appId = dartAppId
    ..instanceId = dartAppInstanceId))));

  try {
    if (modulesToLoad.isNotEmpty) {
      manager.updateGraph();
      return manager.reload(modulesToLoad);
    } else {
      callMethod(getProperty(require('dart_sdk'), 'dart'), 'hotRestart', []);
      runMain();
      return true;
    }
  } finally {
    // Notify webdev that the isolate has been created.
    sseClient.sink.add(jsonEncode(serializers.serialize(IsolateStart((b) => b
      ..appId = dartAppId
      ..instanceId = dartAppInstanceId))));
  }
}

@JS(r'$dartAppId')
external String get dartAppId;

@JS(r'$dartAppInstanceId')
external String get dartAppInstanceId;
@JS(r'$dartAppInstanceId')
external set dartAppInstanceId(String id);

@JS(r'$dartRunMain')
external void Function() get runMain;

@JS(r'$dartHotRestart')
external set hotRestartJs(Promise<bool> Function() cb);

@JS(r'$launchDevTools')
external set launchDevToolsJs(void Function() cb);
@JS(r'$launchDevTools')
external void Function() get launchDevToolsJs;

@JS(r'$dartLoader')
external DartLoader get dartLoader;

@JS(r'$dartReloadConfiguration')
external String get reloadConfiguration;

@JS(r'require')
external Object Function(String module) get require;

List<K> keys<K, V>(JsMap<K, V> map) {
  return List.from(_jsArrayFrom(map.keys()));
}

Future<Map<String, String>> _getDigests() async {
  var request = await HttpRequest.request(dartLoader.appDigests,
      responseType: 'json', method: 'GET');
  return (request.response as Map).cast<String, String>();
}

bool get _isChrome =>
    window.navigator.userAgent.contains('Chrome') &&
    // Edge has `Chrome` in its user agent string, but it also has `Edg` which
    // chrome doesn't.
    !window.navigator.userAgent.contains('Edg');

@JS('Array.from')
external List _jsArrayFrom(Object any);

@JS('Object.keys')
external List _jsObjectKeys(Object any);

@JS('Object.values')
external List _jsObjectValues(Object any);

Module _moduleLibraries(String moduleId) {
  var moduleObj = dartLoader.getModuleLibraries(moduleId);
  if (moduleObj == null) {
    throw HotReloadFailedException("Failed to get module '$moduleId'. "
        "This error might appear if such module doesn't exist or isn't already "
        'loaded');
  }
  var moduleKeys = List<String>.from(_jsObjectKeys(moduleObj));
  var moduleValues =
      List<HotReloadableLibrary>.from(_jsObjectValues(moduleObj));
  var moduleLibraries = moduleValues.map((x) => LibraryWrapper(x));
  return Module(Map.fromIterables(moduleKeys, moduleLibraries));
}

Future<Module> _reloadModule(String moduleId) {
  var completer = Completer<Module>();
  var stackTrace = StackTrace.current;
  dartLoader.forceLoadModule(moduleId, allowInterop(() {
    completer.complete(_moduleLibraries(moduleId));
  }),
      allowInterop((e) => completer.completeError(
          HotReloadFailedException(e.message), stackTrace)));
  return completer.future;
}

void _reloadPage() {
  window.location.reload();
}

@anonymous
@JS()
class DartLoader {
  @JS()
  external String get appDigests;

  @JS()
  external JsMap<String, List<String>> get moduleParentsGraph;

  @JS()
  external void forceLoadModule(String moduleId, void Function() callback,
      void Function(JsError e) onError);

  @JS()
  external Object getModuleLibraries(String moduleId);

  @JS()
  external JsMap<String, String> get urlToModuleId;
}

@anonymous
@JS()
abstract class HotReloadableLibrary {
  /// Implement this function to handle update of child modules.
  ///
  /// May return nullable bool. To indicate that reload of child completes
  /// successfully return true. To indicate that hot-reload is undoable for this
  /// child return false - this will lead to full page reload. If null returned,
  /// reloading will be propagated to current module itself.
  ///
  /// The name of the child will be provided in [childId]. New version of child
  /// module object will be provided in [child].
  /// If any state was saved from previous version, it will be passed to [data].
  ///
  /// This function will be called on old version of module current after child
  /// reloading.
  @JS()
  external bool hot$onChildUpdate(String childId, HotReloadableLibrary child,
      [Object data]);

  /// Implement this function with any code to release resources before destroy.
  ///
  /// Any object returned from this function will be passed to update hooks. Use
  /// it to save any state you need to be preserved between hot reloadings.
  /// Try do not use any custom types here, as it might prevent their code from
  /// reloading. Better serialise to JSON or plain types.
  ///
  /// This function will be called on old version of module before unloading.
  @JS()
  external Object hot$onDestroy();

  /// Implement this function to handle update of the module itself.
  ///
  /// May return nullable bool. To indicate that reload completes successfully
  /// return true. To indicate that hot-reload is undoable return false - this
  /// will lead to full page reload. If null returned, reloading will be
  /// propagated to parent.
  ///
  /// If any state was saved from previous version, it will be passed to [data].
  ///
  /// This function will be called on new version of module after reloading.
  @JS()
  external bool hot$onSelfUpdate([Object data]);
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

class LibraryWrapper implements Library {
  final HotReloadableLibrary _internal;

  LibraryWrapper(this._internal);

  @override
  bool onChildUpdate(String childId, Library child, [Object data]) {
    if (_internal != null && hasProperty(_internal, r'hot$onChildUpdate')) {
      return _internal.hot$onChildUpdate(
          childId, (child as LibraryWrapper)._internal, data);
    }
    // ignore: avoid_returning_null
    return null;
  }

  @override
  Object onDestroy() {
    if (_internal != null && hasProperty(_internal, r'hot$onDestroy')) {
      return _internal.hot$onDestroy();
    }
    return null;
  }

  @override
  bool onSelfUpdate([Object data]) {
    if (_internal != null && hasProperty(_internal, r'hot$onSelfUpdate')) {
      return _internal.hot$onSelfUpdate(data);
    }
    // ignore: avoid_returning_null
    return null;
  }
}
