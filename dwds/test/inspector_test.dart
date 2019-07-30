// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:test/test.dart';
// import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger_test.dart';
import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');
ChromeProxyService get service => context.chromeProxyService;
WipConnection get tabConnection => context.tabConnection;

void main() {
  AppInspector inspector;
  RemoteObject testClass;
  // RemoteObject instance;
  setUpAll(() async {
    await context.setUp();
    inspector = service.appInspectorProvider();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('constructor2', () async {
    var url = 'org-dartlang-app:///web/scopes_main.dart';

    testClass = await inspector.evaluateJsExpression(
        'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["libraryPublicFinal"];');
    var fred = await inspector.instanceRefFor(testClass);
    print(fred);
    var properties = await inspector.debugger.getProperties(testClass.objectId);
    print(properties);
    var stringy = (await inspector
        .sendMessage(testClass, 'toString', []))['value'] as String;
    expect(stringy, 'A test class with message world');
  });

  test('constructor', () async {
    var url = 'org-dartlang-app:///web/scopes_main.dart';
    var library = await inspector.evaluateJsExpression(
        'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]');
    testClass = await inspector.evaluateJsExpression(
        'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["libraryPublicFinal"];');

    var properties;
    // for (var i = 0; i < 10; i++) {
    // try {
    var fred = await inspector.instanceRefFor(testClass);
    print(fred);
    properties = await inspector.debugger.getProperties(testClass.objectId);
    // } catch (e) {
    //   print(e);
    // }
    // }
    print(properties);
    var stringy = (await inspector
        .sendMessage(testClass, 'toString', []))['value'] as String;
    // var stringy = await inspector.sendMessage(testClass, 'toString', []);
    // var testClass2 =
    //     await inspector.loadField(library, 'MyTestClass') as RemoteObject;
    // expect(testClass, isNotNull);
    // expect(testClass2, isNotNull);
    // expect(stringy, '222');
  });
}

