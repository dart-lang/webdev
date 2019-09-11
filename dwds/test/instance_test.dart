// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/utilities/shared.dart';
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
  InstanceHelper instanceHelper;

  setUpAll(() async {
    await context.setUp();
    var chromeProxyService = fetchChromeProxyService(context.debugConnection);
    inspector = chromeProxyService.appInspectorProvider();
    remoteDebugger = chromeProxyService.remoteDebugger;
    debugger = inspector.debugger;
    instanceHelper = InstanceHelper(
        debugger, remoteDebugger, chromeProxyService.appInspectorProvider);
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  final url = 'org-dartlang-app:///web/scopes_main.dart';

  String libraryVariableExpression(String variable) =>
      '$loadModule("dart_sdk").dart.getModuleLibraries("web/scopes_main")'
      '["$url"]["$variable"];';

  Future<RemoteObject> libraryPublicFinal() =>
      inspector.jsEvaluate(libraryVariableExpression('libraryPublicFinal'));

  group('instanceRef', () {
    test('for a null', () async {
      var remoteObject = await libraryPublicFinal();
      var nullVariable = await inspector.loadField(remoteObject, 'notFinal');
      var ref = await instanceHelper.instanceRefFor(nullVariable);
      expect(ref.valueAsString, 'null');
      expect(ref.kind, InstanceKind.kNull);
      var classRef = ref.classRef;
      expect(classRef.name, 'Null');
      expect(classRef.id, 'dart:core:object');
    });

    test('for a double', () async {
      var remoteObject = await libraryPublicFinal();
      var count = await inspector.loadField(remoteObject, 'count');
      var ref = await instanceHelper.instanceRefFor(count);
      expect(ref.valueAsString, '0');
      expect(ref.kind, InstanceKind.kDouble);
      var classRef = ref.classRef;
      expect(classRef.name, 'Double');
      expect(classRef.id, 'dart:core:number');
    });

    test('for a class', () async {
      var remoteObject = await libraryPublicFinal();
      var count = await inspector.loadField(remoteObject, 'myselfField');
      var ref = await instanceHelper.instanceRefFor(count);
      expect(ref.kind, InstanceKind.kPlainInstance);
      var classRef = ref.classRef;
      expect(classRef.name, 'MyTestClass');
      expect(
          classRef.id, 'org-dartlang-app:///web/scopes_main.dart:MyTestClass');
    });

    test('for closure', () async {
      var remoteObject = await libraryPublicFinal();
      var properties = await debugger.getProperties(remoteObject.objectId);
      var closure =
          properties.firstWhere((property) => property.name == 'closure');
      var instanceRef = await instanceHelper.instanceRefFor(closure.value);
      expect(instanceRef.kind, InstanceKind.kClosure);
    });
  });

  group('instance', () {
    test('for class object', () async {
      var remoteObject = await libraryPublicFinal();
      var instance = await instanceHelper.instanceFor(remoteObject);
      expect(instance.kind, InstanceKind.kPlainInstance);
      var classRef = instance.classRef;
      expect(classRef, isNotNull);
      expect(classRef.name, 'MyTestClass');
      var fieldNames =
          instance.fields.map((boundField) => boundField.decl.name).toList();
      expect(fieldNames, [
        '_privateField',
        'closure',
        'count',
        'message',
        'myselfField',
        'notFinal',
        'tornOff',
      ]);
      for (var field in instance.fields) {
        expect(field.decl.declaredType, isNotNull);
      }
    });

    test('for closure', () async {
      var remoteObject = await libraryPublicFinal();
      var properties = await debugger.getProperties(remoteObject.objectId);
      var closure =
          properties.firstWhere((property) => property.name == 'closure');
      var instance = await instanceHelper.instanceFor(closure.value);
      expect(instance.kind, InstanceKind.kClosure);
      var functionName = instance.closureFunction.name;
      // Older SDKs do not contain function names
      if (functionName != 'Closure') {
        expect(functionName, 'someFunction');
      }
      expect(instance.classRef.name, 'Closure');
    });

    test('for a nested class ', () async {
      var libraryRemoteObject = await libraryPublicFinal();
      var fieldRemoteObject =
          await inspector.loadField(libraryRemoteObject, 'myselfField');
      var instance = await instanceHelper.instanceFor(fieldRemoteObject);
      expect(instance.kind, InstanceKind.kPlainInstance);
      var classRef = instance.classRef;
      expect(classRef, isNotNull);
      expect(classRef.name, 'MyTestClass');
    });
  });
}
