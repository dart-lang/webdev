// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:test/test.dart';
// import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');
ChromeProxyService get service => context.chromeProxyService;
WipConnection get tabConnection => context.tabConnection;

void main() {
  AppInspector inspector;
  RemoteObject library;
  RemoteObject testClass;
  // RemoteObject instance;
  setUpAll(() async {
    await context.setUp();
    inspector = service.appInspectorProvider();
    handleErrorIfPresent(await inspector.wipDebugger?.enable() as WipResponse);

  });

  tearDownAll(() async {
    await context.tearDown();
  });

  // VM vm;
  // String isolateId;
  // Stream<Event> stream;
  // ScriptList scripts;
  // ScriptRef mainScript;

  test('constructor', () async {
       var a = await tabConnection.runtime.enable();
    var b = await tabConnection.debugger.enable();
        // await inspector.debugger.pause();
    var url = 'org-dartlang-app:///web/scopes_main.dart';
    // library = await evaluate(
    //     'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]');
    // testClass = await evaluate(
    //     'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["libraryPublicFinal"];');
    testClass = await evaluate("window");

        var properties;
        for (var i = 0; i < 10; i++) {
        try {
          var fred = await inspector.instanceRefFor(testClass);
          print(fred);
           properties = await inspector.debugger.getProperties(testClass.objectId);
        } catch (e) {
          print(e);
        }
        }
        print(properties);
        var stringy = (await inspector.sendMessage(testClass, 'toString', []))['value'] as String;
    // var stringy = await inspector.sendMessage(testClass, 'toString', []);
    var testClass2 =
        await inspector.loadField(library, 'MyTestClass') as RemoteObject;
    expect(testClass, isNotNull);
    expect(testClass2, isNotNull);
    expect(stringy, '222');
  });
}

/// Evaluates expression on global object.
Future<RemoteObject> evaluate(String expression) async {
  final response = await tabConnection.runtime.sendCommand('Runtime.evaluate',
      params: {'expression': expression, 'objectGroup': 'console', 'includeCommandLineAPI': true, 'generatePreview': true});

  if (response.result.containsKey('exceptionDetails')) {
    throw ArgumentError(
        '${response.result['exceptionDetails'] as Map<String, dynamic>}');
  } else {
    return RemoteObject(response.result['result'] as Map<String, dynamic>);
  }
}
