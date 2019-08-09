// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');

WipConnection get tabConnection => context.tabConnection;

void main() {
  AppInspector inspector;
  RemoteDebugger remoteDebugger;
  Debugger debugger;

  setUpAll(() async {
    await context.setUp();
    var chromeProxyService = fetchChromeProxyService(context.debugConnection);
    inspector = chromeProxyService.appInspectorProvider();
    remoteDebugger = chromeProxyService.remoteDebugger;
    debugger = inspector.debugger;
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  final url = 'org-dartlang-app:///web/scopes_main.dart';

  String libraryVariableExpression(String variable) =>
      'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["$variable"];';

  Future<RemoteObject> libraryPublicFinal() => inspector
      .evaluateJsExpression(libraryVariableExpression('libraryPublicFinal'));

  group('instanceRef', () {
    test('for a null', () async {
      var remoteObject = await libraryPublicFinal();
      var nullVariable = await inspector.loadField(remoteObject, 'notFinal');
      var ref = await instanceRefFor(remoteDebugger, nullVariable);
      expect(ref.valueAsString, 'null');
      expect(ref.kind, InstanceKind.kNull);
      var classRef = ref.classRef;
      expect(classRef.name, 'Null');
      expect(classRef.id, 'dart:core:object');
    });

    test('for a double', () async {
      var remoteObject = await libraryPublicFinal();
      var count = await inspector.loadField(remoteObject, 'count');
      var ref = await instanceRefFor(remoteDebugger, count);
      expect(ref.valueAsString, '0');
      expect(ref.kind, InstanceKind.kDouble);
      var classRef = ref.classRef;
      expect(classRef.name, 'Double');
      expect(classRef.id, 'dart:core:number');
    });

    test('for a class', () async {
      var remoteObject = await libraryPublicFinal();
      var count = await inspector.loadField(remoteObject, 'myselfField');
      var ref = await instanceRefFor(remoteDebugger, count);
      expect(ref.kind, InstanceKind.kPlainInstance);
      var classRef = ref.classRef;
      expect(classRef.name, 'MyTestClass');
      expect(
          classRef.id, 'org-dartlang-app:///web/scopes_main.dart:MyTestClass');
    });
  });

  group('instance', () {
    test('for class object', () async {
      var remoteObject = await libraryPublicFinal();
      var instance =
          await instanceFor(debugger, remoteDebugger, remoteObject.objectId);
      expect(instance.kind, InstanceKind.kPlainInstance);
      var classRef = instance.classRef;
      expect(classRef, isNotNull);
      expect(classRef.name, 'MyTestClass');
    });

    test('for a nested class ', () async {
      var libraryRemoteObject = await libraryPublicFinal();
      var fieldRemoteObject =
          await inspector.loadField(libraryRemoteObject, 'myselfField');
      var instance = await instanceFor(
          debugger, remoteDebugger, fieldRemoteObject.objectId);
      expect(instance.kind, InstanceKind.kPlainInstance);
      var classRef = instance.classRef;
      expect(classRef, isNotNull);
      expect(classRef.name, 'MyTestClass');
    });
  });
}
