// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';

import 'restarter.dart';

@JS('dartDevEmbedder')
external _DartDevEmbedder get _dartDevEmbedder;

extension type _DartDevEmbedder._(JSObject _) implements JSObject {
  external _Debugger get debugger;
  external JSPromise<JSAny?> hotRestart();
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

class DdcLibraryBundleRestarter implements Restarter {
  @override
  Future<bool> restart({String? runId, Future? readyToRunMain}) async {
    await _dartDevEmbedder.debugger.maybeInvokeFlutterDisassemble();
    await _dartDevEmbedder.hotRestart().toDart;
    return true;
  }
}
