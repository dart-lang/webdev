// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/utilities/conversions.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');

WipConnection get tabConnection => context.tabConnection;

void main() {
  AppInspector inspector;
  Debugger debugger;

  setUpAll(() async {
    await context.setUp();
    var service = fetchChromeProxyService(context.debugConnection);
    inspector = service.appInspectorProvider();
    debugger = inspector.debugger;
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  final url = 'org-dartlang-app:///web/scopes_main.dart';

  /// A convenient way to get a library variable without boilerplate.
  String libraryVariableExpression(String variable) =>
      '${globalLoadStrategy.loadModuleSnippet}("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["$variable"];';

  Future<RemoteObject> libraryPublicFinal() =>
      inspector.jsEvaluate(libraryVariableExpression('libraryPublicFinal'));

  test('send toString', () async {
    var remoteObject = await libraryPublicFinal();
    var toString = await inspector.invokeMethod(remoteObject, 'toString', []);
    expect(toString.value, 'A test class with message world');
  });

  group('getObject', () {
    test('for class with generic', () async {
      var isolateId = inspector.isolate.id;
      var remoteObject = await libraryPublicFinal();
      var instance = await inspector.getObject(isolateId, remoteObject.objectId)
          as Instance;
      var classRef = instance.classRef;
      var clazz = await inspector.getObject(isolateId, classRef.id) as Class;
      expect(clazz.name, 'MyTestClass<dynamic>');
    });
  });

  group('loadField', () {
    test('for string', () async {
      var remoteObject = await libraryPublicFinal();
      var message = await inspector.loadField(remoteObject, 'message');
      expect(message.value, 'world');
    });

    test('for num', () async {
      var remoteObject = await libraryPublicFinal();
      var count = await inspector.loadField(remoteObject, 'count');
      expect(count.value, 0);
    });
  });

  test('properties', () async {
    var remoteObject = await libraryPublicFinal();
    var properties = await debugger.getProperties(remoteObject.objectId);
    var names =
        properties.map((p) => p.name).where((x) => x != '__proto__').toList();
    var expected = [
      '_privateField',
      'closure',
      'count',
      'message',
      'myselfField',
      'notFinal',
      'tornOff',
    ];
    names.sort();
    expect(names, expected);
  });

  group('invoke', () {
    // We test these here because the test fixture has more complicated members
    // to exercise.

    String isolateId;
    LibraryRef bootstrapLibrary;
    RemoteObject instance;

    setUp(() async {
      isolateId = inspector.isolate.id;
      bootstrapLibrary = inspector.isolate.libraries.first;
      instance = await inspector.evaluate(
          isolateId, bootstrapLibrary.id, 'libraryPublicFinal');
    });

    test('invoke top-level private', () async {
      var remote = await inspector.invoke(isolateId, bootstrapLibrary.id,
          '_libraryPrivateFunction', [dartIdFor(2), dartIdFor(3)]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', 5));
    });

    test('invoke instance private', () async {
      var remote = await inspector.invoke(isolateId, instance.objectId,
          'privateMethod', [dartIdFor('some string')]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>().having((instance) => instance.value,
              'result', 'some string : a private field'));
    });

    test('invoke instance method with object parameter', () async {
      var remote = await inspector
          .invoke(isolateId, instance.objectId, 'equals', [instance.objectId]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', true));
    });

    test('invoke instance method with object parameter 2', () async {
      var libraryPrivateList = await inspector.evaluate(
          isolateId, bootstrapLibrary.id, '_libraryPrivate');
      var remote = await inspector.invoke(isolateId, instance.objectId,
          'equals', [libraryPrivateList.objectId]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', false));
    });

    test('invoke closure stored in an instance field', () async {
      var remote =
          await inspector.invoke(isolateId, instance.objectId, 'closure', []);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', null));
    });

    test('invoke a torn-off method', () async {
      var toString = await inspector.loadField(instance, 'tornOff');
      var result =
          await inspector.invoke(isolateId, toString.objectId, 'call', []);
      expect(
          result,
          const TypeMatcher<RemoteObject>().having((instance) => instance.value,
              'toString', 'A test class with message world'));
    });
  });
}
