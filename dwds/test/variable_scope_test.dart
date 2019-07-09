// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'test_context.dart';

final context = TestContext(
    directory: '../example', path: 'scopes.html', pathToServe: 'web');
ChromeProxyService get service => context.chromeProxyService;
WipConnection get tabConnection => context.tabConnection;

void main() {
  setUpAll(() async {
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  group('variable scope', () {
    VM vm;
    String isolateId;
    Stream<Event> stream;
    ScriptList scripts;
    ScriptRef mainScript;

    // TODO: Be able to set breakpoints before start/reload so we can exercise
    // things that aren't in recurring loops.

    setUp(() async {
      vm = await service.getVM();
      isolateId = vm.isolates.first.id;
      scripts = await service.getScripts(isolateId);
      await service.streamListen('Debug');
      stream = service.onEvent('Debug');
      mainScript = scripts.scripts
          .firstWhere((each) => each.uri.contains('scopes_main.dart'));
    });

    /// Support function for pausing and returning the stack at a line.
    Future<Stack> breakAt(int lineNumber) async {
      var bp =
          await service.addBreakpoint(isolateId, mainScript.id, lineNumber);
      // Wait for breakpoint to trigger.
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);
      // Remove breakpoint so it doesn't impact other tests.
      await service.removeBreakpoint(isolateId, bp.id);
      var stack = await service.getStack(isolateId);
      // Resume as to not impact other tests.
      await service.resume(isolateId);
      return stack;
    }

    test('variables in method', () async {
      var stack = await breakAt(25);
      var frame = stack.frames.first;
      var variableNames = frame.vars.map((variable) => variable.name).toList()
        ..sort();
      expect(variableNames, [
        'another',
        'intLocalInMain',
        'local',
        'nestedFunction',
        'parameter',
        'testClass'
      ]);
    });
  });
}
