// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:test/test.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');
ChromeProxyService get service => context.chromeProxyService;
WipConnection get tabConnection => context.tabConnection;

void main() {
  AppInspector inspector;
  RemoteObject instance;
  setUpAll(() async {
    await context.setUp();
    // TODO(alanknight): A nicer way of getting the inspector.
    inspector = service.appInspectorProvider();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  final url = 'org-dartlang-app:///web/scopes_main.dart';

  /// A convenient way to get a library variable without boilerplate.
  String libraryVariableExpression(String variable) =>
      'require("dart_sdk").dart.getModuleLibraries("web/scopes_main")["$url"]["$variable"];';

  Future<RemoteObject> libraryPublicFinal() => inspector
      .evaluateJsExpression(libraryVariableExpression('libraryPublicFinal'));

  test('send toString', () async {
    instance = await libraryPublicFinal();
    var toString = await inspector.sendMessage(instance, 'toString', []);
    expect(toString, 'A test class with message world');
  });

  test('instanceRef toString', () async {
    instance = await libraryPublicFinal();
    var ref = await inspector.instanceRefFor(instance);
    expect(ref.valueAsString, 'A test class with message world');
  });

  test('get string field', () async {
    instance = await inspector
        .evaluateJsExpression(libraryVariableExpression('libraryPublicFinal'));
    var message = await inspector.loadField(instance, 'message');
    expect(message, 'world');
  });

  test('get Object field', () async {
    instance = await inspector
        .evaluateJsExpression(libraryVariableExpression('libraryPublicFinal'));
    var message = await inspector.loadField(instance, 'myselfField');
    var toString = await inspector.toStringOf(message as RemoteObject);
    expect(toString, 'A test class with message world');
  });

  test('properties', () async {
    instance = await inspector
        .evaluateJsExpression(libraryVariableExpression('libraryPublicFinal'));
    var properties = await inspector.debugger.getProperties(instance.objectId);
    var names =
        properties.map((p) => p.name).where((x) => x != '__proto__').toList();
    var expected = [
      'Symbol(MyTestClass.count)',
      'Symbol(MyTestClass.message)',
      'Symbol(MyTestClass.myselfField)',
      'Symbol(MyTestClass.notFinal)'
    ];
    names.sort();
    expect(expected, names);
  });
}
