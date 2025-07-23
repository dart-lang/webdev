// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void main() {
  // Enable verbose logging for debugging.
  const debug = false;
  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    canaryFeatures: true,
    ddcModuleFormat: ModuleFormat.ddc,
  );
  final project = TestProject.testHotReloadBreakpoints;
  final context = TestContext(project, provider);
  final mainFile = project.dartEntryFileName;
  final callLogMarker = 'callLog';
  final capturedStringMarker = 'capturedString';

  tearDownAll(provider.dispose);

  void makeEdit(String file, String originalString, String newString) {
    if (file == project.dartEntryFileName) {
      context.makeEditToDartEntryFile(
        toReplace: originalString,
        replaceWith: newString,
      );
    } else {
      context.makeEditToDartLibFile(
        libFileName: file,
        toReplace: originalString,
        replaceWith: newString,
      );
    }
  }

  Future<void> makeEditAndRecompile(
    String file,
    String originalString,
    String newString,
  ) async {
    makeEdit(file, originalString, newString);
    await context.recompile(fullRestart: false);
  }

  group('when pause_isolates_on_start is true', () {
    late VmService client;
    late Stream<Event> stream;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          compilationMode: CompilationMode.frontendServer,
          moduleFormat: ModuleFormat.ddc,
          canaryFeatures: true,
        ),
      );
      client = await context.connectFakeClient();
      await client.setFlag('pause_isolates_on_start', 'true');
      await client.streamListen(EventStreams.kDebug);
      stream = client.onDebugEvent;
    });

    tearDown(() async {
      await context.tearDown();
    });

    Future<Breakpoint> addBreakpoint({
      required String file,
      required String breakpointMarker,
    }) async {
      final vm = await client.getVM();
      final isolateId = vm.isolates!.first.id!;
      final scriptList = await client.getScripts(isolateId);
      final scriptRef = scriptList.scripts!.firstWhere(
        (script) => script.uri!.contains(file),
      );
      final bpLine = await context.findBreakpointLine(
        breakpointMarker,
        isolateId,
        scriptRef,
      );
      final breakpointAdded = expectLater(
        stream,
        emitsThrough(_hasKind(EventKind.kBreakpointAdded)),
      );
      final breakpoint = await client.addBreakpointWithScriptUri(
        isolateId,
        scriptRef.uri!,
        bpLine,
      );
      await breakpointAdded;
      return breakpoint;
    }

    Future<void> removeBreakpoint(Breakpoint bp) async {
      final vm = await client.getVM();
      final isolateId = vm.isolates!.first.id!;
      final breakpointRemoved = expectLater(
        stream,
        emitsThrough(_hasKind(EventKind.kBreakpointRemoved)),
      );
      await client.removeBreakpoint(isolateId, bp.id!);
      await breakpointRemoved;
    }

    Future<void> resume() async {
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      await client.resume(isolate.id!);
    }

    // When the program is executing, we want to check that at some point it
    // will execute code that will emit [expectedString].
    Future<void> resumeAndExpectLog(String expectedString) async {
      final completer = Completer<void>();
      final subscription = context.webkitDebugger.onConsoleAPICalled.listen((
        e,
      ) {
        if (e.args.first.value == expectedString) {
          completer.complete();
        }
      });
      await resume();
      await completer.future;
      await subscription.cancel();
    }

    Future<List<Breakpoint>> hotReloadAndHandlePausePost(
      List<({String file, String breakpointMarker, Breakpoint? bp})>
      breakpoints,
    ) async {
      final waitForPausePost = expectLater(
        stream,
        emitsThrough(_hasKind(EventKind.kPausePostRequest)),
      );

      // Initiate the hot reload by loading the sources into the page.
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      final report = await client.reloadSources(isolate.id!);
      expect(report.success, true);

      // Client (e.g. DAP) should listen for this event, remove old breakpoints,
      // reregister breakpoints, and then resume. The following lines imitate
      // what the client should do.
      await waitForPausePost;
      final newBreakpoints = <Breakpoint>[];
      for (final (:bp, :breakpointMarker, :file) in breakpoints) {
        // This could be a new file, so there's no existing breakpoint to
        // remove.
        if (bp != null) await removeBreakpoint(bp);
        newBreakpoints.add(
          await addBreakpoint(file: file, breakpointMarker: breakpointMarker),
        );
      }
      // The resume should complete hot reload and resume the program.
      await resume();
      return newBreakpoints;
    }

    Future<void> callEvaluate() async {
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      final rootLib = isolate.rootLib;
      await client.evaluate(isolate.id!, rootLib!.id!, 'evaluate()');
    }

    // Much like `resumeAndExpectLog`, we need a completer to ensure the log
    // will eventually occur when code is executing.
    Future<void> callEvaluateAndExpectLog(String expectedString) async {
      final completer = Completer<void>();
      final subscription = context.webkitDebugger.onConsoleAPICalled.listen((
        e,
      ) {
        if (e.args.first.value == expectedString) {
          completer.complete();
        }
      });
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      final rootLib = isolate.rootLib;
      await client.evaluate(isolate.id!, rootLib!.id!, 'evaluate()');
      await completer.future;
      await subscription.cancel();
    }

    Future<void> waitForBreakpoint() =>
        expectLater(stream, emitsThrough(_hasKind(EventKind.kPauseBreakpoint)));

    test('empty hot reload keeps breakpoints', () async {
      final genString = 'main gen0';

      final bp = await addBreakpoint(
        file: mainFile,
        breakpointMarker: callLogMarker,
      );

      var breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(genString);

      await context.recompile(fullRestart: false);

      await hotReloadAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker, bp: bp),
      ]);

      breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(genString);
    });

    test('after edit and hot reload, breakpoint is in new file', () async {
      final oldString = 'main gen0';
      final newString = 'main gen1';

      final bp = await addBreakpoint(
        file: mainFile,
        breakpointMarker: callLogMarker,
      );

      var breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(oldString);

      // Modify the string that gets printed.
      await makeEditAndRecompile(mainFile, oldString, newString);

      await hotReloadAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker, bp: bp),
      ]);

      breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(newString);
    });

    test('after adding line, hot reload, removing line, and hot reload, '
        'breakpoint is correct across both hot reloads', () async {
      final genLog = 'main gen0';

      var bp = await addBreakpoint(
        file: mainFile,
        breakpointMarker: callLogMarker,
      );

      var breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(genLog);

      // Add an extra log before the existing log.
      final extraLog = 'hot reload';
      final oldString = "log('";
      final newString = "log('$extraLog');\n$oldString";
      await makeEditAndRecompile(mainFile, oldString, newString);

      bp =
          (await hotReloadAndHandlePausePost([
            (file: mainFile, breakpointMarker: callLogMarker, bp: bp),
          ])).first;

      breakpointFuture = waitForBreakpoint();

      await callEvaluateAndExpectLog(extraLog);

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(genLog);

      // Remove the line we just added.
      await makeEditAndRecompile(mainFile, newString, oldString);

      await hotReloadAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker, bp: bp),
      ]);

      breakpointFuture = waitForBreakpoint();

      final consoleLogs = <String>[];
      final consoleSubscription = context.webkitDebugger.onConsoleAPICalled
          .listen((e) {
            consoleLogs.add(e.args.first.value as String);
          });

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      expect(consoleLogs.contains(extraLog), false);
      await resumeAndExpectLog(genLog);
      await consoleSubscription.cancel();
    });

    test(
      'after adding file and putting breakpoint in it, breakpoint is correctly '
      'registered',
      () async {
        final genLog = 'main gen0';

        final bp = await addBreakpoint(
          file: mainFile,
          breakpointMarker: callLogMarker,
        );

        var breakpointFuture = waitForBreakpoint();

        await callEvaluate();

        // Should break at `callLog`.
        await breakpointFuture;
        await resumeAndExpectLog(genLog);

        // Add a library file, import it, and then refer to it in the log.
        final libFile = 'library.dart';
        final libGenLog = 'lib gen0';
        final libValueMarker = 'libValue';
        context.addLibraryFile(
          libFileName: libFile,
          contents: '''String get libraryValue {
            return '$libGenLog'; // Breakpoint: $libValueMarker
          }''',
        );
        final oldImports = "import 'dart:js_interop';";
        final newImports =
            '$oldImports\n'
            "import 'package:_test_hot_reload_breakpoints/library.dart';";
        makeEdit(mainFile, oldImports, newImports);
        final oldLog = "log('\$mainValue');";
        final newLog = "log('\$libraryValue');";
        await makeEditAndRecompile(mainFile, oldLog, newLog);

        await hotReloadAndHandlePausePost([
          (file: mainFile, breakpointMarker: callLogMarker, bp: bp),
          (file: libFile, breakpointMarker: libValueMarker, bp: null),
        ]);

        breakpointFuture = waitForBreakpoint();

        await callEvaluate();

        // Should break at `callLog`.
        await breakpointFuture;

        breakpointFuture = waitForBreakpoint();

        await resume();
        // Should break at `libValue`.
        await breakpointFuture;
        await resumeAndExpectLog(libGenLog);
      },
    );

    // Test that we wait for all scripts to be parsed first before computing
    // location metadata.
    test('after adding many files and putting breakpoint in the last one,'
        'breakpoint is correctly registered', () async {
      final genLog = 'main gen0';

      final bp = await addBreakpoint(
        file: mainFile,
        breakpointMarker: callLogMarker,
      );

      var breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;
      await resumeAndExpectLog(genLog);

      // Add library files, import them, but only refer to the last one in main.
      final numFiles = 50;
      for (var i = 1; i <= numFiles; i++) {
        final libFile = 'library$i.dart';
        context.addLibraryFile(
          libFileName: libFile,
          contents: '''String get libraryValue$i {
            return 'lib gen$i'; // Breakpoint: libValue$i
          }''',
        );
        final oldImports = "import 'dart:js_interop';";
        final newImports =
            '$oldImports\n'
            "import 'package:_test_hot_reload_breakpoints/$libFile';";
        makeEdit(mainFile, oldImports, newImports);
      }
      final oldLog = "log('\$mainValue');";
      final newLog = "log('\$libraryValue$numFiles');";
      await makeEditAndRecompile(mainFile, oldLog, newLog);

      await hotReloadAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker, bp: bp),
        (
          file: 'library$numFiles.dart',
          breakpointMarker: 'libValue$numFiles',
          bp: null,
        ),
      ]);

      breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `callLog`.
      await breakpointFuture;

      breakpointFuture = waitForBreakpoint();

      await resume();
      // Should break at the breakpoint in the last file.
      await breakpointFuture;
      await resumeAndExpectLog('lib gen$numFiles');
    });

    test('breakpoint in captured code is deleted', () async {
      var bp = await addBreakpoint(
        file: mainFile,
        breakpointMarker: capturedStringMarker,
      );

      final oldLog = "log('\$mainValue');";
      final newLog = "log('\${closure()}');";
      await makeEditAndRecompile(mainFile, oldLog, newLog);

      bp =
          (await hotReloadAndHandlePausePost([
            (file: mainFile, breakpointMarker: capturedStringMarker, bp: bp),
          ])).first;

      final breakpointFuture = waitForBreakpoint();

      await callEvaluate();

      // Should break at `capturedString`.
      await breakpointFuture;
      final oldCapturedString = 'captured closure gen0';
      // Closure gets evaluated for the first time.
      await resumeAndExpectLog(oldCapturedString);

      final newCapturedString = 'captured closure gen1';
      await makeEditAndRecompile(
        mainFile,
        oldCapturedString,
        newCapturedString,
      );

      await hotReloadAndHandlePausePost([
        (file: mainFile, breakpointMarker: capturedStringMarker, bp: bp),
      ]);

      // Breakpoint should not be hit as it's now deleted. We should also see
      // the old string still as the closure has not been reevaluated.
      await callEvaluateAndExpectLog(oldCapturedString);
    });
  }, timeout: Timeout.factor(2));

  group('when pause_isolates_on_start is false', () {
    late VmService client;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          compilationMode: CompilationMode.frontendServer,
          moduleFormat: ModuleFormat.ddc,
          canaryFeatures: true,
        ),
      );
      client = await context.connectFakeClient();
      await client.setFlag('pause_isolates_on_start', 'false');
    });

    tearDown(() async {
      await context.tearDown();
    });

    Future<void> callEvaluateAndExpectLog(String expectedString) async {
      final completer = Completer<void>();
      final subscription = context.webkitDebugger.onConsoleAPICalled.listen((
        e,
      ) {
        if (e.args.first.value == expectedString) {
          completer.complete();
        }
      });
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      final rootLib = isolate.rootLib;
      await client.evaluate(isolate.id!, rootLib!.id!, 'evaluate()');
      await completer.future;
      await subscription.cancel();
    }

    test('no pause when calling reloadSources', () async {
      final oldString = 'main gen0';
      final newString = 'main gen1';

      await callEvaluateAndExpectLog(oldString);

      // Modify the string that gets printed and hot reload.
      await makeEditAndRecompile(mainFile, oldString, newString);
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      final report = await client.reloadSources(isolate.id!);
      expect(report.success, true);

      // Program should not be paused, so this should execute.
      await callEvaluateAndExpectLog(newString);
    });
  }, timeout: Timeout.factor(2));
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
