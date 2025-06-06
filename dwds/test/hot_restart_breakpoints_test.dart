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
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void main() {
  // Enable verbose logging for debugging.
  final debug = false;
  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    canaryFeatures: true,
    ddcModuleFormat: ModuleFormat.ddc,
  );
  final project = TestProject.testHotRestartBreakpoints;
  final context = TestContext(project, provider);
  final mainFile = project.dartEntryFileName;
  final callLogMarker = 'callLog';

  tearDownAll(provider.dispose);

  final edits = <({String file, String originalString, String newString})>[];

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
    edits.add((
      file: file,
      originalString: originalString,
      newString: newString,
    ));
  }

  Future<void> makeEditAndRecompile(
    String file,
    String originalString,
    String newString,
  ) async {
    makeEdit(file, originalString, newString);
    await context.recompile(fullRestart: true);
  }

  void undoEdits() {
    for (var i = edits.length - 1; i >= 0; i--) {
      final edit = edits[i];
      if (edit.file == project.dartEntryFileName) {
        context.makeEditToDartEntryFile(
          toReplace: edit.newString,
          replaceWith: edit.originalString,
        );
      } else {
        context.makeEditToDartLibFile(
          libFileName: edit.file,
          toReplace: edit.newString,
          replaceWith: edit.originalString,
        );
      }
    }
    edits.clear();
  }

  group('when pause_isolates_on_start is true', () {
    late VmService client;
    late VmServiceInterface service;
    late Stream<Event> stream;
    // Fetch the log statements that are sent to console.
    final consoleLogs = <String>[];
    late StreamSubscription<ConsoleAPIEvent> consoleSubscription;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          compilationMode: CompilationMode.frontendServer,
          moduleFormat: provider.ddcModuleFormat,
          canaryFeatures: provider.canaryFeatures,
        ),
      );
      client = await context.connectFakeClient();
      await client.setFlag('pause_isolates_on_start', 'true');
      await client.streamListen('Isolate');
      service = context.service;
      await service.streamListen('Debug');
      stream = service.onEvent('Debug');
      consoleSubscription = context.webkitDebugger.onConsoleAPICalled.listen(
        (e) => consoleLogs.add(e.args.first.value as String),
      );
    });

    tearDown(() async {
      await consoleSubscription.cancel();
      consoleLogs.clear();
      undoEdits();
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
      return await client.addBreakpointWithScriptUri(
        isolateId,
        scriptRef.uri!,
        bpLine,
      );
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
      final newSubscription = context.webkitDebugger.onConsoleAPICalled.listen((
        e,
      ) {
        if (e.args.first.value == expectedString) {
          completer.complete();
        }
      });
      await resume();
      await completer.future.then((_) {
        newSubscription.cancel();
      });
    }

    Future<void> hotRestartAndHandlePausePost(
      List<({String file, String breakpointMarker})> breakpoints,
    ) async {
      final eventsDone = expectLater(
        client.onIsolateEvent,
        emitsThrough(
          emitsInOrder([
            _hasKind(EventKind.kIsolateExit),
            _hasKind(EventKind.kIsolateStart),
            _hasKind(EventKind.kIsolateRunnable),
          ]),
        ),
      );

      final waitForPausePost = stream.firstWhere(
        (event) => event.kind == EventKind.kPausePostRequest,
      );

      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      expect(
        await client.callServiceExtension(hotRestart!),
        const TypeMatcher<Success>(),
      );

      await eventsDone;

      // DWDS defers running main after a hot restart until the client (e.g.
      // DAP) resumes. Client should listen for this event, remove breakpoints
      // (we don't remove them here as DWDS already removes them), and
      // reregister breakpoints (which will be registered in the new files), and
      // resume.
      await waitForPausePost;
      // Verify DWDS has already removed the breakpoints at this point.
      final vm = await client.getVM();
      final isolate = await service.getIsolate(vm.isolates!.first.id!);
      expect(isolate.breakpoints, isEmpty);
      for (final breakpoint in breakpoints) {
        await addBreakpoint(
          file: breakpoint.file,
          breakpointMarker: breakpoint.breakpointMarker,
        );
      }
      await resume();
    }

    Future<Event> waitForBreakpoint() =>
        stream.firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

    test('after edit and hot restart, breakpoint is in new file', () async {
      final oldLog = 'main gen0';
      final newLog = 'main gen1';

      await addBreakpoint(file: mainFile, breakpointMarker: callLogMarker);

      await makeEditAndRecompile(mainFile, oldLog, newLog);

      final breakpointFuture = waitForBreakpoint();

      await hotRestartAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker),
      ]);

      // Should break at `callLog`.
      await breakpointFuture;
      expect(consoleLogs.contains(newLog), false);
      await resumeAndExpectLog(newLog);
    });

    test('after adding line, hot restart, removing line, and hot restart, '
        'breakpoint is correct across both hot restarts', () async {
      final genLog = 'main gen0';

      await addBreakpoint(file: mainFile, breakpointMarker: callLogMarker);

      // Add an extra log before the existing log.
      final extraLog = 'hot reload';
      final oldString = "log('";
      final newString = "log('$extraLog');\n$oldString";
      await makeEditAndRecompile(mainFile, oldString, newString);

      var breakpointFuture = waitForBreakpoint();

      await hotRestartAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker),
      ]);

      // Should break at `callLog`.
      await breakpointFuture;
      expect(consoleLogs.contains(extraLog), true);
      expect(consoleLogs.contains(genLog), false);
      await resumeAndExpectLog(genLog);

      consoleLogs.clear();

      // Remove the line we just added.
      await makeEditAndRecompile(mainFile, newString, oldString);

      breakpointFuture = waitForBreakpoint();

      await hotRestartAndHandlePausePost([
        (file: mainFile, breakpointMarker: callLogMarker),
      ]);

      // Should break at `callLog`.
      await breakpointFuture;
      expect(consoleLogs.contains(extraLog), false);
      expect(consoleLogs.contains(genLog), false);
      await resumeAndExpectLog(genLog);
    });

    test(
      'after adding file and putting breakpoint in it, breakpoint is correctly '
      'registered',
      () async {
        final genLog = 'main gen0';

        await addBreakpoint(file: mainFile, breakpointMarker: callLogMarker);

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
            "import 'package:_test_hot_restart_breakpoints/library.dart';";
        makeEdit(mainFile, oldImports, newImports);
        final oldLog = "log('$genLog');";
        final newLog = "log('\$libraryValue');";
        await makeEditAndRecompile(mainFile, oldLog, newLog);

        var breakpointFuture = waitForBreakpoint();

        await hotRestartAndHandlePausePost([
          (file: mainFile, breakpointMarker: callLogMarker),
          (file: libFile, breakpointMarker: libValueMarker),
        ]);

        // Should break at `callLog`.
        await breakpointFuture;
        expect(consoleLogs.contains(libGenLog), false);

        breakpointFuture = waitForBreakpoint();

        await resume();
        // Should break at `libValue`.
        await breakpointFuture;
        expect(consoleLogs.contains(libGenLog), false);
        await resumeAndExpectLog(libGenLog);

        context.removeLibraryFile(libFileName: libFile);
      },
    );
  });
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
