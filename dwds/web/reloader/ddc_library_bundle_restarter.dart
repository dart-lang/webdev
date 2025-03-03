// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

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

  Future<void> maybeInvokeFlutterReassemble() async {
    final method = 'ext.flutter.reassemble';
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
  @override
  Future<bool> restart({String? runId, Future? readyToRunMain}) async {
    await _dartDevEmbedder.debugger.maybeInvokeFlutterDisassemble();
    await _dartDevEmbedder.hotRestart().toDart;
    return true;
  }

  @override
  Future<void> reload(String hotReloadSourcesPath) async {
    final completer = Completer<String>();
    final xhr = _XMLHttpRequest();
    xhr.withCredentials = true;
    xhr.onreadystatechange =
        () {
          // If the request has completed and OK, or the response has not changed.
          if (xhr.readyState == 4 && xhr.status == 200 || xhr.status == 304) {
            completer.complete(xhr.responseText);
          }
        }.toJS;
    xhr.get(hotReloadSourcesPath, true);
    xhr.send();
    final responseText = await completer.future;

    final srcLibraries = (json.decode(responseText) as List).cast<Map>();
    final filesToLoad = JSArray<JSString>();
    final librariesToReload = JSArray<JSString>();
    for (final srcLibrary in srcLibraries) {
      final srcLibraryCast = srcLibrary.cast<String, Object>();
      filesToLoad.push((srcLibraryCast['src'] as String).toJS);
      final libraries = (srcLibraryCast['libraries'] as List).cast<String>();
      for (final library in libraries) {
        librariesToReload.push(library.toJS);
      }
    }
    await _dartDevEmbedder.hotReload(filesToLoad, librariesToReload).toDart;
    // TODO(srujzs): Reassembling is slow. It's roughly almost the time it takes
    // to recompile and do a hot reload. We should do some better profiling and
    // see if we can improve this.
    await _dartDevEmbedder.debugger.maybeInvokeFlutterReassemble();
  }
}
