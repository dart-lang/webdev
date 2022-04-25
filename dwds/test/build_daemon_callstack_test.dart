// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

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

class TestSetup {
  static final contextUnsound = TestContext(
      directory: p.join('..', 'fixtures', '_testPackage'),
      entry: p.join('..', 'fixtures', '_testPackage', 'web', 'main.dart'),
      path: 'index.html',
      pathToServe: 'web');

  static final contextSound = TestContext(
      directory: p.join('..', 'fixtures', '_testPackageSound'),
      entry: p.join('..', 'fixtures', '_testPackageSound', 'web', 'main.dart'),
      path: 'index.html',
      pathToServe: 'web');

  TestContext context;

  TestSetup.sound() : context = contextSound;

  TestSetup.unsound() : context = contextUnsound;

  ChromeProxyService get service =>
      fetchChromeProxyService(context.debugConnection);
  WipConnection get tabConnection => context.tabConnection;
}

void main() {
  group('shared context |', () {
    // Enable verbose logging for debugging.
    var debug = false;

    for (var soundNullSafety in [false, true]) {
      var setup = soundNullSafety ? TestSetup.sound() : TestSetup.unsound();
      var context = setup.context;

      group('${soundNullSafety ? "" : "no "}sound null safety |', () {
        setUpAll(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(enableExpressionEvaluation: true);
        });

        tearDownAll(() async {
          await context.tearDown();
        });

        group('callStack |', () {
          ChromeProxyService service;
          VM vm;
          Isolate isolate;
          ScriptList scripts;
          ScriptRef mainScript;
          Stream<Event> stream;

          setUp(() async {
            setCurrentLogWriter(debug: debug);
            service = setup.service;
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

          Future<void> onBreakPoint(ScriptRef script, String breakPointId,
              Future<void> Function() body) async {
            Breakpoint bp;
            try {
              var line = await context.findBreakpointLine(
                  breakPointId, isolate.id, script);
              bp = await setup.service
                  .addBreakpointWithScriptUri(isolate.id, script.uri, line);

              expect(bp, isNotNull);
              expect(bp.location, _matchBpLocation(mainScript, line, 0));

              await stream.firstWhere(
                  (Event event) => event.kind == EventKind.kPauseBreakpoint);

              await body();
            } finally {
              // Remove breakpoint so it doesn't impact other tests or retries.
              if (bp != null) {
                await setup.service.removeBreakpoint(isolate.id, bp.id);
              }
            }
          }

          Future<void> testCallStack(
              List<String> bpIds, List<String> functions) async {
            // Find lines the breakpoints are located on.
            var lines = await Future.wait(bpIds.map((bpId) =>
                context.findBreakpointLine(bpId, isolate.id, mainScript)));

            // Get current stack.
            var stack = await service.getStack(isolate.id);

            // Verify the stack is correct.
            expect(stack.frames.length, greaterThanOrEqualTo(lines.length));
            var expected = [
              for (var i = 0; i < lines.length; i++)
                _matchFrame(mainScript, functions[i], lines[i])
            ];
            expect(stack.frames, containsAll(expected));

            // Verify that expression evaluation is not failing.
            var instance = await service.evaluateInFrame(isolate.id, 1, 'main');
            expect(instance, isA<InstanceRef>());
          }

          test('breakpoint succeeds with correct callstack', () async {
            // Breakpoint IDs.
            var bpIds = [
              'printEnclosingObject',
              'printEnclosingFunctionMultiLine',
              'callPrintEnclosingFunctionMultiLine',
            ];
            // Functions breakpoints are located in.
            var functions = [
              'printEnclosingObject',
              'printNestedObjectsMultiLine',
              '<closure>',
            ];
            await onBreakPoint(
                mainScript, bpIds[0], () => testCallStack(bpIds, functions));
          });

          test('breakpoint inside a line gives correct callstack', () async {
            // Breakpoint IDs.
            var bpIds = [
              'newEnclosedClass',
              'printNestedObjectMultiLine',
              'callPrintEnclosingFunctionMultiLine',
            ];
            // Functions breakpoints are located in.
            var functions = [
              'new',
              'printNestedObjectsMultiLine',
              '<closure>',
            ];
            await onBreakPoint(
                mainScript, bpIds[0], () => testCallStack(bpIds, functions));
          });

          test('breakpoint gives correct callstack after step out', () async {
            // Breakpoint IDs.
            var bpIds = [
              'printEnclosingObjectMultiLine',
              'callPrintEnclosingFunctionMultiLine',
            ];
            // Functions breakpoints are located in.
            var functions = [
              'printNestedObjectsMultiLine',
              '<closure>',
            ];
            await onBreakPoint(mainScript, 'newEnclosedClass', () async {
              await service.resume(isolate.id, step: 'Out');
              await stream.firstWhere(
                  (Event event) => event.kind == EventKind.kPauseInterrupted);
              return testCallStack(bpIds, functions);
            });
          });

          test('breakpoint gives correct callstack after step in', () async {
            // Breakpoint IDs.
            var bpIds = [
              'newEnclosedClass',
              'printNestedObjectMultiLine',
              'callPrintEnclosingFunctionMultiLine',
            ];
            // Functions breakpoints are located in.
            var functions = [
              'new',
              'printNestedObjectsMultiLine',
              '<closure>',
            ];
            await onBreakPoint(mainScript, 'printNestedObjectMultiLine',
                () async {
              await service.resume(isolate.id, step: 'Into');
              await stream.firstWhere(
                  (Event event) => event.kind == EventKind.kPauseInterrupted);
              return testCallStack(bpIds, functions);
            });
          });

          test('breakpoint gives correct callstack after step into chain calls',
              () async {
            // Breakpoint IDs.
            var bpIds = [
              'createObjectWithMethod',
              // This is currently incorrect, should be printObjectMultiLine.
              // See issue: https://github.com/dart-lang/sdk/issues/48874
              'printMultiLine',
              'callPrintObjectMultiLine',
            ];
            // Functions breakpoints are located in.
            var functions = [
              'createObject',
              'printObjectMultiLine',
              '<closure>',
            ];
            await onBreakPoint(mainScript, 'printMultiLine', () async {
              await service.resume(isolate.id, step: 'Into');
              await stream.firstWhere(
                  (Event event) => event.kind == EventKind.kPauseInterrupted);
              return testCallStack(bpIds, functions);
            });
          });
        });
      });
    }
  });
}

Matcher _matchFrame(ScriptRef script, String function, int line) => isA<Frame>()
    .having((frame) => frame.code.name, 'function', function)
    .having((frame) => frame.location, 'location',
        _matchFrameLocation(script, line));

Matcher _matchBpLocation(ScriptRef script, int line, int column) =>
    isA<SourceLocation>()
        .having((loc) => loc.script, 'script', equals(script))
        .having((loc) => loc.line, 'line', equals(line))
        .having((loc) => loc.column, 'column', greaterThanOrEqualTo(column));

Matcher _matchFrameLocation(ScriptRef script, int line) => isA<SourceLocation>()
    .having((loc) => loc.script, 'script', equals(script))
    .having((loc) => loc.line, 'line', equals(line));
