// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/utilities/conversions.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:test/test.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');

WipConnection get tabConnection => context.tabConnection;

void main() {
  AppInspector inspector;

  setUpAll(() async {
    await context.setUp();
    // TODO(alanknight): A nicer way of getting the inspector.
    inspector =
        fetchChromeProxyService(context.debugConnection).appInspectorProvider();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  final url = 'org-dartlang-app:///web/scopes_main.dart';

  /// A convenient way to get a library variable without boilerplate.
  String libraryVariableExpression(String variable) =>
      '$loadModule("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["$variable"];';

  Future<RemoteObject> libraryPublicFinal() =>
      inspector.jsEvaluate(libraryVariableExpression('libraryPublicFinal'));

  test('send toString', () async {
    var remoteObject = await libraryPublicFinal();
    var toString = await inspector.invokeMethod(remoteObject, 'toString', []);
    expect(toString.value, 'A test class with message world');
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
    var properties =
        await inspector.debugger.getProperties(remoteObject.objectId);
    var names =
        properties.map((p) => p.name).where((x) => x != '__proto__').toList();
    var expected = [
      '_privateField',
      'closure',
      'count',
      'message',
      'myselfField',
      'notFinal'
    ];
    names.sort();
    expect(names, expected);
  });

  group('invoke', () {
    // We test these here because the test fixture has more complicated members to
    // exercise.

    String isolateId;
    String libraryId;
    RemoteObject instance;

    setUp(() async {
      isolateId = inspector.isolate.id;
      libraryId = inspector.isolate.rootLib.id;
      instance =
          await inspector.evaluate(isolateId, libraryId, 'libraryPublicFinal');
    });

    test('invoke top-level private', () async {
      var remote = await inspector.invoke(isolateId, libraryId,
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
      var libraryPrivateList =
          await inspector.evaluate(isolateId, libraryId, '_libraryPrivate');
      var remote = await inspector.invoke(isolateId, instance.objectId,
          'equals', [libraryPrivateList.objectId]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', false));
    });
  });
}
