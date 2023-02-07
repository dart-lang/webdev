// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/logging.dart';

class TestSetup {
  TestContext context;

  TestSetup.sound()
      : context = TestContext.withSoundNullSafety(
          packageName: '_experimentSound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: 'index.html',
        );

  ChromeProxyService get service =>
      fetchChromeProxyService(context.debugConnection);
}

void main() async {
  // Enable verbose logging for debugging.
  final debug = false;

  for (var compilationMode in CompilationMode.values) {
    await _runTests(
      compilationMode: compilationMode,
      debug: debug,
    );
  }
}

Future<void> _runTests({
  required CompilationMode compilationMode,
  required bool debug,
}) async {
  final setup = TestSetup.sound();
  final context = setup.context;
  late VmServiceInterface service;
  late Stream<Event> stream;
  late String isolateId;
  late ScriptRef mainScript;

  onBreakPoint(breakPointId, body) => _onBreakPoint(
        setup,
        stream,
        isolateId,
        mainScript,
        breakPointId,
        body,
      );

  group('$compilationMode |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        compilationMode: compilationMode,
        enableExpressionEvaluation: true,
        verboseCompiler: debug,
        experiments: ['records'],
      );
      service = setup.service;

      final vm = await service.getVM();
      isolateId = vm.isolates!.first.id!;
      final scripts = await service.getScripts(isolateId);

      await service.streamListen('Debug');
      stream = service.onEvent('Debug');

      mainScript = scripts.scripts!
          .firstWhere((each) => each.uri!.contains('main.dart'));
    });

    tearDownAll(context.tearDown);

    setUp(() => setCurrentLogWriter(debug: debug));
    tearDown(() => service.resume(isolateId));

    test('simple records', () async {
      await onBreakPoint('printSimpleLocal', (event) async {
        final frame = event.topFrame!.index!;
        final result = await service.evaluateInFrame(
          isolateId,
          frame,
          'record',
        );

        expect(result, isA<InstanceRef>());
        return result as InstanceRef;
      });
    });
  });
}

Future<void> _onBreakPoint(
  TestSetup setup,
  Stream<Event> stream,
  String isolateId,
  ScriptRef script,
  String breakPointId,
  Future<void> Function(Event event) body,
) async {
  final context = setup.context;
  final service = setup.service;

  Breakpoint? bp;
  try {
    final line =
        await context.findBreakpointLine(breakPointId, isolateId, script);
    bp = await service.addBreakpointWithScriptUri(isolateId, script.uri!, line);

    final event =
        await stream.firstWhere((e) => e.kind == EventKind.kPauseBreakpoint);

    await body(event);
  } finally {
    // Remove breakpoint so it doesn't impact other tests or retries.
    if (bp != null) {
      await service.removeBreakpoint(isolateId, bp.id!);
    }
  }
}
