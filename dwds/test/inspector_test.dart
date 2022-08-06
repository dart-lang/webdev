// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@TestOn('vm')
import 'package:dwds/dwds.dart';
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
    final service = fetchChromeProxyService(context.debugConnection);
    inspector = service.inspector;
    debugger = await service.debuggerFuture;
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

  Future<RemoteObject> libraryPrivate() =>
      inspector.jsEvaluate(libraryVariableExpression('_libraryPrivate'));

  group('jsEvaluate', () {
    test('no error', () async {
      await expectLater(inspector.jsEvaluate('42'),
          completion(isA<RemoteObject>().having((e) => e.value, 'value', 42)));
    });

    test('syntax error', () async {
      await expectLater(
          () => inspector.jsEvaluate('<'),
          throwsA(isA<ChromeDebugException>()
              .having((e) => e.text, 'text', 'Uncaught')
              .having((e) => e.exception.description, 'description',
                  contains('SyntaxError'))
              .having((e) => e.stackTrace, 'stackTrace', isNull)
              .having((e) => e.evalContents, 'evalContents', '<')));
    });

    test('evaluation error', () async {
      await expectLater(
          () => inspector.jsEvaluate('''
        (function() {
          let foo = (function() {
            console.log(boo);
          });
          foo();
        })();
        '''),
          throwsA(isA<ChromeDebugException>()
              .having((e) => e.text, 'text', 'Uncaught')
              .having((e) => e.exception.description, 'description',
                  contains('ReferenceError'))
              .having((e) => e.stackTrace.printFrames()[0], 'stackTrace',
                  contains('foo()'))
              .having((e) => e.evalContents, 'evalContents', contains('foo'))));
    });
  });

  test('send toString', () async {
    final remoteObject = await libraryPublicFinal();
    final toString =
        await inspector.invoke(remoteObject.objectId, 'toString', []);
    expect(toString.value, 'A test class with message world');
  });

  group('getObject', () {
    test('for class with generic', () async {
      final remoteObject = await libraryPublicFinal();
      final instance =
          await inspector.getObject(remoteObject.objectId) as Instance;
      final classRef = instance.classRef;
      final clazz = await inspector.getObject(classRef.id) as Class;
      expect(clazz.name, 'MyTestClass<dynamic>');
    });
  });

  group('loadField', () {
    test('for string', () async {
      final remoteObject = await libraryPublicFinal();
      final message = await inspector.loadField(remoteObject, 'message');
      expect(message.value, 'world');
    });

    test('for num', () async {
      final remoteObject = await libraryPublicFinal();
      final count = await inspector.loadField(remoteObject, 'count');
      expect(count.value, 0);
    });
  });

  test('properties', () async {
    final remoteObject = await libraryPublicFinal();
    final properties = await debugger.getProperties(remoteObject.objectId);
    final names =
        properties.map((p) => p.name).where((x) => x != '__proto__').toList();
    final expected = [
      '_privateField',
      'abstractField',
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

    LibraryRef bootstrapLibrary;
    RemoteObject instance;

    setUp(() async {
      bootstrapLibrary = inspector.isolate.rootLib;
      instance = await libraryPublicFinal();
    });

    test('invoke top-level private', () async {
      final remote = await inspector.invoke(bootstrapLibrary.id,
          '_libraryPrivateFunction', [dartIdFor(2), dartIdFor(3)]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', 5));
    });

    test('invoke instance private', () async {
      final remote = await inspector.invoke(
          instance.objectId, 'privateMethod', [dartIdFor('some string')]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>().having((instance) => instance.value,
              'result', 'some string : a private field'));
    });

    test('invoke instance method with object parameter', () async {
      final remote = await inspector
          .invoke(instance.objectId, 'equals', [instance.objectId]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', true));
    });

    test('invoke instance method with object parameter 2', () async {
      final libraryPrivateList = await libraryPrivate();
      final remote = await inspector
          .invoke(instance.objectId, 'equals', [libraryPrivateList.objectId]);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', false));
    });

    test('invoke closure stored in an instance field', () async {
      final remote = await inspector.invoke(instance.objectId, 'closure', []);
      expect(
          remote,
          const TypeMatcher<RemoteObject>()
              .having((instance) => instance.value, 'result', null));
    });

    test('invoke a torn-off method', () async {
      final toString = await inspector.loadField(instance, 'tornOff');
      final result = await inspector.invoke(toString.objectId, 'call', []);
      expect(
          result,
          const TypeMatcher<RemoteObject>().having((instance) => instance.value,
              'toString', 'A test class with message world'));
    });
  });
}