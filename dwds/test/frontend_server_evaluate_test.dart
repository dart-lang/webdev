// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@Tags(['frontend-server'])
@TestOn('vm')
import 'dart:async';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';
import 'fixtures/logging.dart';

final context = TestContext(
    directory: p.join('..', 'fixtures', '_testPackage'),
    entry: p.join('..', 'fixtures', '_testPackage', 'web', 'main.dart'),
    path: 'index.html',
    pathToServe: 'web');

ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);
WipConnection get tabConnection => context.tabConnection;

void main() async {
  group('shared context with evaluation', () {
    setUpAll(() async {
      // Note: change 'printOnFailure' to 'print' for debug printing
      configureLogWriter(
          customLogWriter: (level, message,
                  {loggerName, error, stackTrace, verbose}) =>
              printOnFailure('[$level] $loggerName: $message'));

      await context.setUp(
          enableExpressionEvaluation: true,
          compilationMode: CompilationMode.frontendServer,
          verbose: false);
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('evaluateInFrame', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;
      Stream<Event> stream;

      setUp(() async {
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        scripts = await service.getScripts(isolate.id);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      tearDown(() async {
        await service.resume(isolate.id);
      });

      test('local', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'local');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '42'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });

      test('global', () async {
        var line = await context.findBreakpointLine(
            'printGlobal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'testLibraryValue');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '3'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });

      test('call core function', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'print(local)');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', 'null'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });

      test('call library function with const param', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'testLibraryFunction(42)');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '42'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });

      test('call library function with local param', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'testLibraryFunction(local)');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '42'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });

      test('loop variable', () async {
        var line = await context.findBreakpointLine(
            'printLoopVariable', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'item');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '1'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      }, tags: ['dev-sdk']);

      test('error', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var error = await service.evaluateInFrame(
            isolate.id, event.topFrame.index, 'typo');

        expect(
            error,
            const TypeMatcher<ErrorRef>().having(
                (instance) => instance.message,
                'message',
                'CompilationError: Getter not found: \'typo\'.\ntypo\n^^^^'));

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });
    });
  });

  group('shared context with no evaluation', () {
    setUpAll(() async {
      await context.setUp(
          enableExpressionEvaluation: false,
          compilationMode: CompilationMode.frontendServer,
          verbose: false);
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('evaluateInFrame', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;
      Stream<Event> stream;

      setUp(() async {
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        scripts = await service.getScripts(isolate.id);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      tearDown(() async {
        await service.resume(isolate.id);
      });

      test('cannot evaluate expression', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        expect(
            () => service.evaluateInFrame(
                isolate.id, event.topFrame.index, 'local'),
            throwsRPCError);

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });
    });
  });
}
