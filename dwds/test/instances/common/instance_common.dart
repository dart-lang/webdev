// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/utilities.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../fixtures/context.dart';
import '../../fixtures/project.dart';
import '../../fixtures/utilities.dart';
import 'test_inspector.dart';

void runTypeSystemVerificationTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required bool canaryFeatures,
  required bool debug,
}) {
  final project = TestProject.testScopesWithSoundNullSafety;

  group('$compilationMode |', () {
    final context = TestContext(project, provider);
    late AppInspector inspector;

    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          canaryFeatures: canaryFeatures,
        ),
      );
      final chromeProxyService = context.service;
      inspector = chromeProxyService.inspector;
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    final url = 'org-dartlang-app:///example/scopes/main.dart';

    String libraryName(CompilationMode compilationMode) =>
        compilationMode == CompilationMode.frontendServer
            ? "example/scopes/main.dart"
            : "example/scopes/main";

    String libraryVariableTypeExpression(
      String variable,
      CompilationMode compilationMode,
    ) =>
        '''
            (function() {
              var dart = ${globalToolConfiguration.loadStrategy.loadModuleSnippet}('dart_sdk').dart;
              var libraryName = '${libraryName(compilationMode)}';
              var library = dart.getModuleLibraries(libraryName)['$url'];
              var x = library['$variable'];
              return dart.getReifiedType(x);
            })();
          ''';

    group('compiler', () {
      setUp(() => setCurrentLogWriter(debug: debug));

      test('uses correct type system', () async {
        final remoteObject = await inspector.jsEvaluate(
          libraryVariableTypeExpression(
            'libraryPublicFinal',
            compilationMode,
          ),
        );
        expect(
          remoteObject.json['className'],
          canaryFeatures ||
                  dartSdkIsAtLeast(
                    newDdcTypeSystemVersion,
                  )
              ? 'dart_rti.Rti.new'
              : 'Function',
        );
      });
    });
  });
}

void runTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required bool canaryFeatures,
  required bool debug,
}) {
  final project = TestProject.testScopesWithSoundNullSafety;
  final context = TestContext(project, provider);

  late AppInspector inspector;

  group('$compilationMode |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          canaryFeatures: canaryFeatures,
        ),
      );
      final chromeProxyService = context.service;
      inspector = chromeProxyService.inspector;
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    final url = 'org-dartlang-app:///example/scopes/main.dart';

    String libraryName(CompilationMode compilationMode) =>
        compilationMode == CompilationMode.frontendServer
            ? "example/scopes/main.dart"
            : "example/scopes/main";

    String libraryVariableExpression(
      String variable,
      CompilationMode compilationMode,
    ) =>
        '${globalToolConfiguration.loadStrategy.loadModuleSnippet}("dart_sdk").dart.'
        'getModuleLibraries("${libraryName(compilationMode)}")'
        '["$url"]["$variable"];';

    String newInterceptorsExpression(String type) =>
        'new (require("dart_sdk")._interceptors.$type).new()';

    final String newDartError = 'new (require("dart_sdk").dart).DartError';

    /// A reference to the the variable `libraryPublicFinal`, an instance of
    /// `MyTestClass`.
    Future<RemoteObject> libraryPublicFinal(CompilationMode compilationMode) =>
        inspector.jsEvaluate(
          libraryVariableExpression('libraryPublicFinal', compilationMode),
        );

    /// A reference to the the variable `libraryPublic`, a List of Strings.
    Future<RemoteObject> libraryPublic(CompilationMode compilationMode) =>
        inspector.jsEvaluate(
          libraryVariableExpression('libraryPublic', compilationMode),
        );

    group('instanceRef', () {
      setUp(() => setCurrentLogWriter(debug: debug));

      test('for a null', () async {
        final remoteObject = await libraryPublicFinal(compilationMode);
        final nullVariable =
            await inspector.loadField(remoteObject, 'notFinal');
        final ref = await inspector.instanceRefFor(nullVariable);
        expect(ref!.valueAsString, 'null');
        expect(ref.kind, InstanceKind.kNull);
        final classRef = ref.classRef!;
        expect(classRef.name, 'Null');
        expect(classRef.id, 'classes|dart:core|Null');
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for a double', () async {
        final remoteObject = await libraryPublicFinal(compilationMode);
        final count = await inspector.loadField(remoteObject, 'count');
        final ref = await inspector.instanceRefFor(count);
        expect(ref!.valueAsString, '0');
        expect(ref.kind, InstanceKind.kDouble);
        final classRef = ref.classRef!;
        expect(classRef.name, 'Double');
        expect(classRef.id, 'classes|dart:core|Double');
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for an object', () async {
        final remoteObject = await libraryPublicFinal(compilationMode);
        final count = await inspector.loadField(remoteObject, 'myselfField');
        final ref = await inspector.instanceRefFor(count);
        expect(ref!.kind, InstanceKind.kPlainInstance);
        final classRef = ref.classRef!;
        expect(classRef.name, 'MyTestClass<dynamic>');
        expect(
            classRef.id,
            'classes|org-dartlang-app:///example/scopes/main.dart'
            '|MyTestClass<dynamic>');
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for a closure', () async {
        final remoteObject = await libraryPublicFinal(compilationMode);
        final properties =
            await inspector.getProperties(remoteObject.objectId!);
        final closure =
            properties.firstWhere((property) => property.name == 'closure');
        final ref = await inspector.instanceRefFor(closure.value!);
        final functionName = ref!.closureFunction!.name;
        // Older SDKs do not contain function names
        if (functionName != 'Closure') {
          expect(functionName, 'someFunction');
        }
        expect(ref.kind, InstanceKind.kClosure);
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for a list', () async {
        final remoteObject = await libraryPublic(compilationMode);
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.length, greaterThan(0));
        expect(ref.kind, InstanceKind.kList);
        expect(ref.classRef!.name, matchListClassName('String'));
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for map', () async {
        final remoteObject = await inspector
            .jsEvaluate(libraryVariableExpression('map', compilationMode));
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.length, 2);
        expect(ref.kind, InstanceKind.kMap);
        expect(ref.classRef!.name, 'LinkedMap<Object, Object>');
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for an IdentityMap', () async {
        final remoteObject = await inspector.jsEvaluate(
          libraryVariableExpression('identityMap', compilationMode),
        );
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.length, 2);
        expect(ref.kind, InstanceKind.kMap);
        expect(ref.classRef!.name, 'IdentityMap<String, int>');
        expect(inspector.isDisplayableObject(ref), isTrue);
      });

      test('for a Dart error', () async {
        final remoteObject = await inspector.jsEvaluate(newDartError);
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.kind, InstanceKind.kPlainInstance);
        expect(ref.classRef!.name, 'NativeError');
        expect(inspector.isDisplayableObject(ref), isFalse);
        expect(inspector.isNativeJsError(ref), isTrue);
        expect(inspector.isNativeJsObject(ref), isFalse);
      });

      test('for a native JavaScript error', () async {
        final remoteObject = await inspector
            .jsEvaluate(newInterceptorsExpression('NativeError'));
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.kind, InstanceKind.kPlainInstance);
        expect(ref.classRef!.name, 'NativeError');
        expect(inspector.isDisplayableObject(ref), isFalse);
        expect(inspector.isNativeJsError(ref), isTrue);
        expect(inspector.isNativeJsObject(ref), isFalse);
      });

      test('for a native JavaScript type error', () async {
        final remoteObject = await inspector
            .jsEvaluate(newInterceptorsExpression('JSNoSuchMethodError'));
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.kind, InstanceKind.kPlainInstance);
        expect(ref.classRef!.name, 'JSNoSuchMethodError');
        expect(inspector.isDisplayableObject(ref), isFalse);
        expect(inspector.isNativeJsError(ref), isTrue);
        expect(inspector.isNativeJsObject(ref), isFalse);
      });

      test('for a native JavaScript object', () async {
        final remoteObject = await inspector
            .jsEvaluate(newInterceptorsExpression('LegacyJavaScriptObject'));
        final ref = await inspector.instanceRefFor(remoteObject);
        expect(ref!.kind, InstanceKind.kPlainInstance);
        expect(ref.classRef!.name, 'LegacyJavaScriptObject');
        expect(inspector.isDisplayableObject(ref), isFalse);
        expect(inspector.isNativeJsError(ref), isFalse);
        expect(inspector.isNativeJsObject(ref), isTrue);
      });
    });

    group('instance', () {
      setUp(() => setCurrentLogWriter(debug: debug));
      test('for an object', () async {
        final remoteObject = await libraryPublicFinal(compilationMode);
        final instance = await inspector.instanceFor(remoteObject);
        expect(instance!.kind, InstanceKind.kPlainInstance);
        final classRef = instance.classRef!;
        expect(classRef, isNotNull);
        expect(classRef.name, 'MyTestClass<dynamic>');
        final boundFieldNames = instance.fields!
            .map((boundField) => boundField.decl!.name)
            .toList();
        expect(boundFieldNames, [
          '_privateField',
          'abstractField',
          'closure',
          'count',
          'message',
          'myselfField',
          'notFinal',
          'tornOff',
        ]);
        final fieldNames =
            instance.fields!.map((boundField) => boundField.name).toList();
        expect(boundFieldNames, fieldNames);
        for (var field in instance.fields!) {
          expect(field.name, isNotNull);
          expect(field.decl!.declaredType, isNotNull);
        }
        expect(inspector.isDisplayableObject(instance), isTrue);
      });

      test('for closure', () async {
        final remoteObject = await libraryPublicFinal(compilationMode);
        final properties =
            await inspector.getProperties(remoteObject.objectId!);
        final closure =
            properties.firstWhere((property) => property.name == 'closure');
        final instance = await inspector.instanceFor(closure.value!);
        expect(instance!.kind, InstanceKind.kClosure);
        expect(instance.classRef!.name, 'Closure');
        expect(inspector.isDisplayableObject(instance), isTrue);
      });

      test('for a nested object', () async {
        final libraryRemoteObject = await libraryPublicFinal(compilationMode);
        final fieldRemoteObject =
            await inspector.loadField(libraryRemoteObject, 'myselfField');
        final instance = await inspector.instanceFor(fieldRemoteObject);
        expect(instance!.kind, InstanceKind.kPlainInstance);
        final classRef = instance.classRef!;
        expect(classRef, isNotNull);
        expect(classRef.name, 'MyTestClass<dynamic>');
        expect(inspector.isDisplayableObject(instance), isTrue);
      });

      test('for a list', () async {
        final remote = await libraryPublic(compilationMode);
        final instance = await inspector.instanceFor(remote);
        expect(instance!.kind, InstanceKind.kList);
        final classRef = instance.classRef!;
        expect(classRef, isNotNull);
        expect(classRef.name, matchListClassName('String'));
        final first = instance.elements![0];
        expect(first.valueAsString, 'library');
        expect(inspector.isDisplayableObject(instance), isTrue);
      });

      test('for a map', () async {
        final remote = await inspector
            .jsEvaluate(libraryVariableExpression('map', compilationMode));
        final instance = await inspector.instanceFor(remote);
        expect(instance!.kind, InstanceKind.kMap);
        final classRef = instance.classRef!;
        expect(classRef.name, 'LinkedMap<Object, Object>');
        final first = instance.associations![0].value as InstanceRef;
        expect(first.kind, InstanceKind.kList);
        expect(first.length, 3);
        final second = instance.associations![1].value as InstanceRef;
        expect(second.kind, InstanceKind.kString);
        expect(second.valueAsString, 'something');
        expect(inspector.isDisplayableObject(instance), isTrue);
      });

      test('for an identityMap', () async {
        final remote = await inspector.jsEvaluate(
          libraryVariableExpression('identityMap', compilationMode),
        );
        final instance = await inspector.instanceFor(remote);
        expect(instance!.kind, InstanceKind.kMap);
        final classRef = instance.classRef!;
        expect(classRef.name, 'IdentityMap<String, int>');
        final first = instance.associations![0].value;
        expect(first.valueAsString, '1');
        expect(inspector.isDisplayableObject(instance), isTrue);
      });

      test('for a Dart error', () async {
        final remoteObject = await inspector.jsEvaluate(newDartError);
        final instance = await inspector.instanceFor(remoteObject);
        expect(instance!.kind, InstanceKind.kPlainInstance);
        expect(instance.classRef!.name, 'NativeError');
        expect(inspector.isDisplayableObject(instance), isFalse);
        expect(inspector.isNativeJsError(instance), isTrue);
        expect(inspector.isNativeJsObject(instance), isFalse);
      });

      test('for a native JavaScript error', () async {
        final remoteObject = await inspector
            .jsEvaluate(newInterceptorsExpression('NativeError'));
        final instance = await inspector.instanceFor(remoteObject);
        expect(instance!.kind, InstanceKind.kPlainInstance);
        expect(instance.classRef!.name, 'NativeError');
        expect(inspector.isDisplayableObject(instance), isFalse);
        expect(inspector.isNativeJsError(instance), isTrue);
        expect(inspector.isNativeJsObject(instance), isFalse);
      });

      test('for a native JavaScript type error', () async {
        final remoteObject = await inspector
            .jsEvaluate(newInterceptorsExpression('JSNoSuchMethodError'));
        final instance = await inspector.instanceFor(remoteObject);
        expect(instance!.kind, InstanceKind.kPlainInstance);
        expect(instance.classRef!.name, 'JSNoSuchMethodError');
        expect(inspector.isDisplayableObject(instance), isFalse);
        expect(inspector.isNativeJsError(instance), isTrue);
        expect(inspector.isNativeJsObject(instance), isFalse);
      });

      test('for a native JavaScript object', () async {
        final remoteObject = await inspector
            .jsEvaluate(newInterceptorsExpression('LegacyJavaScriptObject'));
        final instance = await inspector.instanceFor(remoteObject);
        expect(instance!.kind, InstanceKind.kPlainInstance);
        expect(instance.classRef!.name, 'LegacyJavaScriptObject');
        expect(inspector.isDisplayableObject(instance), isFalse);
        expect(inspector.isNativeJsError(instance), isFalse);
        expect(inspector.isNativeJsObject(instance), isTrue);
      });
    });
  });
}
