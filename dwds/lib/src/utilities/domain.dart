// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

// @dart = 2.9

import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../connections/app_connection.dart';
import '../debugging/remote_debugger.dart';

abstract class AppInspectorInterface {
  AppConnection get appConnection;
  Isolate get isolate;
  IsolateRef get isolateRef;

  RemoteDebugger get remoteDebugger;

  /// Returns the ID for the execution context or null if not found.
  Future<int> get contextId;

  /// Calls Chrome's Runtime.callFunctionOn method.
  ///
  /// [evalExpression] should be a JS function definition that can accept
  /// [arguments].
  Future<RemoteObject> jsCallFunctionOn(RemoteObject receiver,
      String evalExpression, List<RemoteObject> arguments,
      {bool returnByValue = false});

  /// Returns the [ScriptRef] for the provided Dart server path [uri].
  Future<ScriptRef> scriptRefFor(String uri);

  /// Look up the script by id in an isolate.
  ScriptRef scriptWithId(String scriptId);

  /// Returns the [LibraryRef] for the provided Dart [objectId].
  Future<LibraryRef> libraryRefFor(String objectId);

  /// Returns the [Library] for the provided Dart [objectId].
  Future<Library> getLibrary(String objectId);

  /// Returns the [ScriptRef]s in the library with [libraryId].
  Future<List<ScriptRef>> scriptRefsForLibrary(String libraryId);

  /// Create an InstanceRef for an object, which may be a RemoteObject, or may
  /// be something returned by value from Chrome, e.g. number, boolean, or
  /// String.
  Future<InstanceRef> instanceRefFor(Object value);

  /// Get the value of the field named [fieldName] from [receiver].
  Future<RemoteObject> loadField(RemoteObject receiver, String fieldName);

  /// Convert a JS exception description into a description containing
  /// a Dart stack trace.
  Future<String> mapExceptionStackTrace(String description);

  /// Call [function] with objects referred by [argumentIds] as arguments.
  Future<RemoteObject> callFunction(
      String function, Iterable<String> argumentIds);

  /// Invoke the function named [selector] on the object identified by
  /// [targetId].
  ///
  /// The [targetId] can be the URL of a Dart library, in which case this means
  /// invoking a top-level function. The [arguments] are always strings that are
  /// Dart object Ids (which can also be Chrome RemoteObject objectIds that are
  /// for non-Dart JS objects.)
  Future<RemoteObject> invoke(
      String targetId, String selector, List<dynamic> arguments);

  /// Evaluate [expression] by calling Chrome's Runtime.evaluate.
  Future<RemoteObject> jsEvaluate(String expression);

  Future<Obj> getObject(String objectId, {int offset, int count});

  /// All the scripts in the isolate.
  Future<ScriptList> getScripts();

  /// Return the VM SourceReport for the given parameters.
  ///
  /// Currently this implements the 'PossibleBreakpoints' report kind.
  Future<SourceReport> getSourceReport(
    List<String> reports, {
    String scriptId,
    int tokenPos,
    int endTokenPos,
    bool forceCompile,
    bool reportLines,
    List<String> libraryFilters,
  });

  Future<MemoryUsage> getMemoryUsage();
}

/// A common superclass to allow implementations of different parts of the
/// protocol to get access to the inspector and utility functions.
///
/// Subclasses should call the super constructor with the AppInspectorProvider.
abstract class Domain {
  Domain();

  AppInspectorInterface inspector;

  /// Validate that isolateId matches the current isolate we're connected to and
  /// return that isolate.
  ///
  /// This is useful to call at the beginning of API methods that are passed an
  /// isolate id.
  Isolate checkIsolate(String methodName, String isolateId) {
    if (isolateId != inspector.isolate?.id) {
      throwSentinel(methodName, SentinelKind.kCollected,
          'Unrecognized isolateId: $isolateId');
    }
    return inspector.isolate;
  }
}

void throwInvalidParam(String method, String message) {
  throw RPCError(method, RPCError.kInvalidParams, message);
}

void throwSentinel(String method, String kind, String message) {
  final data = <String, String>{'kind': kind, 'valueAsString': message};
  throw SentinelException.parse(method, data);
}
