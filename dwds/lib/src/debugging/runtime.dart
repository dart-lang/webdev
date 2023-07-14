// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class DebuggerRuntime {
  final _logger = Logger('DebuggerRuntime');
  final AppInspectorInterface _inspector;

  DebuggerRuntime(this._inspector);

  static String _jsRuntimeCall(
    String call, {
    List<String> params = const <String>[],
  }) =>
      '''
      function(${params.join(', ')}) {
        const sdk = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk');
        const dart = sdk.dart;
        return dart.$call;
      }
      ''';

  Future<RemoteObject?> getLibraryMetadata(String libraryUri) async {
    final call = _jsRuntimeCall('getLibraryMetadata("$libraryUri")');
    print('Runtime call: $call');
    RemoteObject? result;
    try {
      result = await _inspector.jsEvaluate(call, returnByValue: true);
    } on ChromeDebugException catch (_) {
      // Unreferenced libraries are not loaded at runtime,
      // return empty library object for consistency among
      // VM Service implementations.
      // TODO: Collect library and class information from debug symbols.
      _logger.warning('Library $libraryUri is not loaded. '
          'This can happen for unreferenced libraries.');
    }
    return result;
  }

  Future<RemoteObject> getClassMetadata(
    String libraryUri,
    String className,
  ) async {
    final call = _jsRuntimeCall(
      "getClassMetadata('$libraryUri', '$className')",
    );
    return _inspector.jsEvaluate(call, returnByValue: true);

    // TODO: can we use _inspector.jsEvaluate?
    /* RemoteObject result;
    try {
      result = await _inspector.remoteDebugger.evaluate(
        call,
        returnByValue: true,
        contextId: await _inspector.contextId,
      );
    } on ExceptionDetails catch (e) {
      throw ChromeDebugException(e.json, evalContents: call);
    }
    return result;*/
  }

  Future<RemoteObject> getFunctionName(RemoteObject object) {
    final call = _jsRuntimeCall("getFunctionName(this)");
    return _inspector.jsCallFunctionOn(object, call, [], returnByValue: true);
  }

  Future<RemoteObject> getObjectMetadata(RemoteObject object) {
    final call = _jsRuntimeCall("getObjectMetadata(this)");
    return _inspector.jsCallFunctionOn(object, call, [], returnByValue: true);
  }

  Future<RemoteObject> getLibrary(String libraryUri) {
    final call = _jsRuntimeCall("getLibrary('$libraryUri')");
    return _inspector.jsEvaluate(call);
  }

  Future<RemoteObject> getMapElements(RemoteObject map) {
    final call = _jsRuntimeCall("getMapElements(this)");
    return _inspector.jsCallFunctionOn(map, call, []);
  }

  Future<RemoteObject> getSetElements(RemoteObject set) {
    final call = _jsRuntimeCall("getSetElements(this)");
    return _inspector.jsCallFunctionOn(set, call, []);
  }

  Future<RemoteObject> getRecordFields(
    RemoteObject record,
  ) {
    final call = _jsRuntimeCall("getRecordFields(this)");
    return _inspector.jsCallFunctionOn(record, call, []);
  }

  Future<RemoteObject> getTypeFields(RemoteObject type) {
    final call = _jsRuntimeCall("getTypeFields(this)");
    return _inspector.jsCallFunctionOn(type, call, []);
  }

  Future<RemoteObject> getRecordTypeFields(RemoteObject recordType) {
    final call = _jsRuntimeCall("getRecordTypeFields(this)");
    return _inspector.jsCallFunctionOn(recordType, call, []);
  }

  Future<RemoteObject> getObjectFieldNames(RemoteObject object) {
    final call = _jsRuntimeCall("getObjectFieldNames(this)");
    return _inspector.jsCallFunctionOn(object, call, [], returnByValue: true);
  }

  Future<RemoteObject> loadField(RemoteObject receiver, String fieldName) {
    final call = _jsRuntimeCall("dloadRepl(this, '$fieldName')");
    return _inspector.jsCallFunctionOn(receiver, call, []);
  }

  Future<RemoteObject> subRange(
    RemoteObject object,
    RemoteObject offset,
    RemoteObject count,
  ) {
    final call = _jsRuntimeCall(
      'getSubRange(this, offset, count)',
      params: ['offset', 'count'],
    );
    return _inspector.jsCallFunctionOn(object, call, [offset, count]);
  }
}
