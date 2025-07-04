// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dwds/src/utilities/shared.dart';

import 'restarter.dart';

@JS('dartDevEmbedder')
external _DartDevEmbedder get _dartDevEmbedder;

extension type _DartDevEmbedder._(JSObject _) implements JSObject {
  external _Debugger get debugger;
  external JSPromise<JSAny?> hotRestart();
  external JSPromise<JSAny?> hotReload(
    JSArray<JSString> filesToLoad,
    JSArray<JSString> librariesToReload,
  );
  external _DartDevEmbedderConfig get config;
}

extension type _DartDevEmbedderConfig._(JSObject _) implements JSObject {
  external JSFunction? capturedMainHandler;
  external JSFunction? capturedHotReloadEndHandler;
}

extension type _Debugger._(JSObject _) implements JSObject {
  external JSPromise<JSString> invokeExtension(String key, String params);
  external JSArray<JSString> get extensionNames;

  Future<void> maybeInvokeFlutterDisassemble() async {
    final method = 'ext.flutter.disassemble';
    if (extensionNames.toDart.contains(method.toJS)) {
      await invokeExtension(method, '{}').toDart;
    }
  }
}

@JS('XMLHttpRequest')
extension type _XMLHttpRequest._(JSObject _) implements JSObject {
  external _XMLHttpRequest();
  external set withCredentials(bool value);
  external set onreadystatechange(JSFunction fun);
  external void open(String method, String url, bool async);
  void get(String url, bool async) => open('GET', url, async);
  external void send();
  external int get readyState;
  external int get status;
  external String get responseText;
}

extension on JSArray<JSString> {
  external void push(JSString value);
}

class DdcLibraryBundleRestarter implements Restarter {
  JSFunction? _capturedHotReloadEndCallback;

  Future<void> _runMainWhenReady(
    Future? readyToRunMain,
    JSFunction runMain,
  ) async {
    if (readyToRunMain != null) {
      await readyToRunMain;
    }

    runMain.callAsFunction();
  }

  @override
  Future<bool> restart({String? runId, Future? readyToRunMain}) async {
    await _dartDevEmbedder.debugger.maybeInvokeFlutterDisassemble();
    final mainHandler =
        (JSFunction runMain) {
          _dartDevEmbedder.config.capturedMainHandler = null;
          safeUnawaited(_runMainWhenReady(readyToRunMain, runMain));
        }.toJS;
    _dartDevEmbedder.config.capturedMainHandler = mainHandler;
    await _dartDevEmbedder.hotRestart().toDart;
    return true;
  }

  @override
  Future<JSObject> hotReloadStart(String hotReloadSourcesPath) async {
    final completer = Completer<String>();
    final xhr = _XMLHttpRequest();
    xhr.withCredentials = true;
    xhr.onreadystatechange =
        () {
          // If the request has completed and OK, or the response has not
          // changed.
          if (xhr.readyState == 4 && xhr.status == 200 || xhr.status == 304) {
            completer.complete(xhr.responseText);
          }
        }.toJS;
    xhr.get(hotReloadSourcesPath, true);
    xhr.send();
    final responseText = await completer.future;

    final srcModuleLibraries = (json.decode(responseText) as List).cast<Map>();
    final filesToLoad = JSArray<JSString>();
    final moduleMap = JSObject();
    final librariesToReload = JSArray<JSString>();
    for (final srcModuleLibrary in srcModuleLibraries) {
      final srcModuleLibraryCast = srcModuleLibrary.cast<String, Object>();
      filesToLoad.push((srcModuleLibraryCast['src'] as String).toJS);
      final module = srcModuleLibraryCast['module'] as String;
      final libraries =
          (srcModuleLibraryCast['libraries'] as List).cast<String>();
      moduleMap[module] = libraries.jsify();
      for (final library in libraries) {
        librariesToReload.push(library.toJS);
      }
    }
    _dartDevEmbedder.config.capturedHotReloadEndHandler =
        (JSFunction hotReloadEndCallback) {
          _capturedHotReloadEndCallback = hotReloadEndCallback;
        }.toJS;
    await _dartDevEmbedder.hotReload(filesToLoad, librariesToReload).toDart;
    return moduleMap;
  }

  @override
  Future<void> hotReloadEnd() async {
    // Requires a previous call to `hotReloadStart`.
    _capturedHotReloadEndCallback!.callAsFunction();
    _dartDevEmbedder.config.capturedHotReloadEndHandler = null;
    _capturedHotReloadEndCallback = null;
  }
}
