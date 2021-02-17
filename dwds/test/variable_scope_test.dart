// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/dart_scope.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');
ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);
WipConnection get tabConnection => context.tabConnection;

void main() {
  setUpAll(() async {
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  group('ddcTemporaryVariableRegExp', () {
    test('matches correctly', () {
      expect(ddcTemporaryVariableRegExp.hasMatch(r't4$'), isTrue);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't4$0'), isTrue);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't4$10'), isTrue);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't4$0'), isTrue);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't1'), isTrue);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't10'), isTrue);

      expect(ddcTemporaryVariableRegExp.hasMatch(r't'), isFalse);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't10foo'), isFalse);
      expect(ddcTemporaryVariableRegExp.hasMatch(r't$10foo'), isFalse);
    });
  });

  group('variable scope', () {
    VM vm;
    String isolateId;
    Stream<Event> stream;
    ScriptList scripts;
    ScriptRef mainScript;
    Stack stack;

    // TODO: Be able to set breakpoints before start/reload so we can exercise
    // things that aren't in recurring loops.

    /// Support function for pausing and returning the stack at a line.
    Future<Stack> breakAt(String breakpointId, ScriptRef scriptRef) async {
      var lineNumber =
          await context.findBreakpointLine(breakpointId, isolateId, scriptRef);

      var bp = await service.addBreakpoint(isolateId, scriptRef.id, lineNumber);
      // Wait for breakpoint to trigger.
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);
      // Remove breakpoint so it doesn't impact other tests.
      await service.removeBreakpoint(isolateId, bp.id);
      var stack = await service.getStack(isolateId);
      return stack;
    }

    setUp(() async {
      vm = await service.getVM();
      isolateId = vm.isolates.first.id;
      scripts = await service.getScripts(isolateId);
      await service.streamListen('Debug');
      stream = service.onEvent('Debug');
      mainScript = scripts.scripts
          .firstWhere((each) => each.uri.contains('scopes_main.dart'));
    });

    tearDown(() async {
      await service.resume(isolateId);
    });

    test('variables in static function', () async {
      stack = await breakAt('staticFunction', mainScript);
      var frame = stack.frames.first;
      var variableNames = frame.vars.map((variable) => variable.name).toList()
        ..sort();
      expect(variableNames, containsAll(['formal']));
    });

    test('variables in function', () async {
      stack = await breakAt('nestedFunction', mainScript);
      var frame = stack.frames.first;
      var variableNames = frame.vars.map((variable) => variable.name).toList()
        ..sort();
      expect(
          variableNames,
          containsAll([
            'aClass',
            'another',
            'intLocalInMain',
            'local',
            'localThatsNull',
            'nestedFunction',
            'parameter',
            'testClass'
          ]));
    });

    test('variables in closure nested in method', () async {
      stack = await breakAt('nestedClosure', mainScript);
      var frame = stack.frames.first;
      var variableNames = frame.vars.map((variable) => variable.name).toList()
        ..sort();
      expect(variableNames,
          ['closureLocalInsideMethod', 'local', 'parameter', 'this']);
    });

    test('variables in method', () async {
      stack = await breakAt('printMethod', mainScript);
      var frame = stack.frames.first;
      var variableNames = frame.vars.map((variable) => variable.name).toList()
        ..sort();
      expect(variableNames, ['this']);
    });

    test('evaluateJsOnCallFrame', () async {
      stack = await breakAt('nestedFunction', mainScript);
      var inspector = service.appInspectorProvider();
      var debugger = inspector.debugger;
      var parameter = await debugger.evaluateJsOnCallFrameIndex(0, 'parameter');
      expect(parameter.value, matches(RegExp(r'\d+ world')));
      var ticks = await debugger.evaluateJsOnCallFrameIndex(1, 'ticks');
      // We don't know how many ticks there were before we stopped, but it should
      // be a positive number.
      expect(ticks.value, isPositive);
    });
  });
}
