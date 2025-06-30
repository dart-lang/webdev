// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/services/expression_compiler.dart' show ModuleFormat;
import 'package:path/path.dart' show basename;
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import '../../fixtures/context.dart';
import '../../fixtures/project.dart';
import '../../fixtures/utilities.dart';
import 'test_inspector.dart';

void runTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required bool canaryFeatures,
  required bool debug,
}) {
  final context = TestContext(TestProject.testExperiment, provider);
  final testInspector = TestInspector(context);

  late VmService service;
  late Stream<Event> stream;
  late String isolateId;
  late ScriptRef mainScript;

  Future<void> onBreakpoint(
    String breakPointId,
    Future<void> Function(Event) body,
  ) => testInspector.onBreakPoint(
    stream,
    isolateId,
    mainScript,
    breakPointId,
    body,
  );

  Future<InstanceRef> getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  group('$compilationMode | dot shorthands:', () {
    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          enableExpressionEvaluation: true,
          verboseCompiler: debug,
          experiments: ['dot-shorthands'],
          canaryFeatures: canaryFeatures,
          moduleFormat: provider.ddcModuleFormat,
        ),
      );
      service = context.debugConnection.vmService;

      final vm = await service.getVM();
      isolateId = vm.isolates!.first.id!;
      final scripts = await service.getScripts(isolateId);

      await service.streamListen(EventStreams.kDebug);
      stream = service.onDebugEvent;

      mainScript = scripts.scripts!.firstWhere(
        (each) => each.uri!.contains('main.dart'),
      );
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('expression evaluation and single-stepping', () async {
      await onBreakpoint('testDotShorthands', (event) async {
        final frame = event.topFrame!.index!;

        var instanceRef = await getInstanceRef(frame, '(c = .two).value');
        expect(instanceRef.valueAsString, '2');

        instanceRef = await getInstanceRef(frame, '(c = .three).value');
        expect(instanceRef.valueAsString, '3');

        instanceRef = await getInstanceRef(frame, '(c = .four()).value');
        expect(instanceRef.valueAsString, '4');

        final scriptBasename = basename(mainScript.uri!);

        const lineA = 116;
        const lineB = 118;
        const lineC = 119;
        const lineD = 120;
        const lineE = 127;
        const lineF = 129;
        const lineG = 131;
        const lineH = 132;

        final expected = [
          '$scriptBasename:$lineE:3', // on 'c'
          // TODO(2638): Investigate why this conditional exclusion is needed.
          if (provider.ddcModuleFormat == ModuleFormat.ddc)
            '$scriptBasename:$lineB:20', // on '2'
          '$scriptBasename:$lineF:3', // on 'c'
          '$scriptBasename:$lineC:25', // on 'C'
          '$scriptBasename:$lineA:10', // on 'v' of 'value'
          '$scriptBasename:$lineA:16', // on ';'
          '$scriptBasename:$lineC:27', // on '3'
          '$scriptBasename:$lineG:3', // on 'c'
          '$scriptBasename:$lineD:22', // on 'C'
          '$scriptBasename:$lineA:10', // on 'v' of 'value'
          '$scriptBasename:$lineA:16', // on ';'
          '$scriptBasename:$lineD:24', // on '4'
          '$scriptBasename:$lineH:3', // on 'p' of 'print'
        ];

        final stops = <String>[];
        await testInspector.runStepIntoThroughProgramRecordingStops(
          isolateId,
          stops,
          provider.ddcModuleFormat == ModuleFormat.ddc ? 13 : 12,
        );

        expect(stops, expected);
      });
    });
  });
}
