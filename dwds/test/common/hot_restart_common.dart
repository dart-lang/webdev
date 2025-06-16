// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';

import 'package:dwds/dwds.dart';
import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import '../fixtures/context.dart';
import '../fixtures/project.dart';
import '../fixtures/utilities.dart';

const originalString = 'Hello World!';
const newString = 'Bonjour le monde!';

void runTests({
  required TestSdkConfigurationProvider provider,
  required ModuleFormat moduleFormat,
  required CompilationMode compilationMode,
  required bool canaryFeatures,
  required bool debug,
}) {
  final context = TestContext(TestProject.testAppendBody, provider);

  tearDownAll(provider.dispose);

  Future<void> recompile({bool hasEdits = false}) async {
    if (compilationMode == CompilationMode.frontendServer) {
      await context.recompile(fullRestart: true);
    } else {
      assert(compilationMode == CompilationMode.buildDaemon);
      if (hasEdits) {
        // Only gets a new build if there were edits.
        await context.waitForSuccessfulBuild(propagateToBrowser: true);
      }
    }
  }

  Future<void> makeEditAndRecompile() async {
    context.makeEditToDartEntryFile(
      toReplace: originalString,
      replaceWith: newString,
    );
    await recompile(hasEdits: true);
  }

  /// Wait for main to finish executing before checking expectations by checking
  /// for a log output.
  ///
  /// If [debuggingEnabled] is false, we can't check for Chrome logs and instead
  /// wait 1 second.
  // TODO(srujzs): We should do something less prone to race conditions when
  // debugging is disabled.
  Future<void> waitForMainToExecute({bool debuggingEnabled = true}) async {
    if (!debuggingEnabled) return Future.delayed(const Duration(seconds: 1));
    final completer = Completer<void>();
    final expectedString = 'main executed';
    final subscription = context.webkitDebugger.onConsoleAPICalled.listen((e) {
      if (e.args.first.value == expectedString) {
        completer.complete();
      }
    });
    await completer.future;
    await subscription.cancel();
  }

  group(
    'Injected client with live reload',
    () {
      group('and with debugging', () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              reloadConfiguration: ReloadConfiguration.liveReload,
              compilationMode: compilationMode,
              moduleFormat: provider.ddcModuleFormat,
              canaryFeatures: provider.canaryFeatures,
            ),
          );
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can live reload changes ', () async {
          final mainDone = waitForMainToExecute();
          await makeEditAndRecompile();
          await mainDone;
          final source = await context.webDriver.pageSource;

          // A full reload should clear the state.
          expect(source.contains(originalString), isFalse);
          expect(source.contains(newString), isTrue);
        });
      });

      group('and without debugging', () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              reloadConfiguration: ReloadConfiguration.liveReload,
              compilationMode: compilationMode,
              moduleFormat: provider.ddcModuleFormat,
              canaryFeatures: provider.canaryFeatures,
            ),
            debugSettings: TestDebugSettings.noDevTools().copyWith(
              enableDebugging: false,
            ),
          );
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can live reload changes ', () async {
          final mainDone = waitForMainToExecute(debuggingEnabled: false);
          await makeEditAndRecompile();
          await mainDone;
          final source = await context.webDriver.pageSource;

          // A full reload should clear the state.
          expect(source.contains(originalString), isFalse);
          expect(source.contains(newString), isTrue);
        });
      });

      group('and without debugging using WebSockets', () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              reloadConfiguration: ReloadConfiguration.liveReload,
              compilationMode: compilationMode,
              moduleFormat: provider.ddcModuleFormat,
              canaryFeatures: provider.canaryFeatures,
            ),
            debugSettings: TestDebugSettings.noDevTools().copyWith(
              enableDebugging: false,
              useSse: false,
            ),
          );
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can live reload changes ', () async {
          final mainDone = waitForMainToExecute(debuggingEnabled: false);
          await makeEditAndRecompile();
          await mainDone;
          final source = await context.webDriver.pageSource;

          // A full reload should clear the state.
          expect(source.contains(originalString), isFalse);
          expect(source.contains(newString), isTrue);
        });
      });
    },
    // `BuildResult`s are only ever emitted when using the build daemon.
    skip: compilationMode != CompilationMode.buildDaemon,
    timeout: Timeout.factor(2),
  );

  group('Injected client', () {
    late VmService fakeClient;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          compilationMode: compilationMode,
          moduleFormat: provider.ddcModuleFormat,
          canaryFeatures: provider.canaryFeatures,
        ),
      );
      fakeClient = await context.connectFakeClient();
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('destroys and recreates the isolate during a hot restart', () async {
      final client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await makeEditAndRecompile();

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

      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      expect(
        await fakeClient.callServiceExtension(hotRestart!),
        const TypeMatcher<Success>(),
      );

      await eventsDone;
    });

    test('can execute simultaneous hot restarts', () async {
      final client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await makeEditAndRecompile();

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

      // Execute two hot restart calls in parallel.
      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      final done = Future.wait([
        fakeClient.callServiceExtension(hotRestart!),
        fakeClient.callServiceExtension(hotRestart),
      ]);
      expect(await done, [
        const TypeMatcher<Success>(),
        const TypeMatcher<Success>(),
      ]);

      // The debugger is still working.
      final vm = await client.getVM();
      final isolateId = vm.isolates!.first.id!;
      final isolate = await client.getIsolate(isolateId);
      final library = isolate.rootLib!.uri!;

      final result = await client.evaluate(isolateId, library, 'true');
      expect(
        result,
        isA<InstanceRef>().having(
          (instance) => instance.valueAsString,
          'valueAsString',
          'true',
        ),
      );

      await eventsDone;
    });

    test('destroys and recreates the isolate during a page refresh', () async {
      final client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await makeEditAndRecompile();

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

      await context.webDriver.driver.refresh();

      await eventsDone;
    });

    test('can hot restart via the service extension', () async {
      final client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await makeEditAndRecompile();

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
      final mainDone = waitForMainToExecute();
      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      expect(
        await fakeClient.callServiceExtension(hotRestart!),
        const TypeMatcher<Success>(),
      );

      await eventsDone;
      await mainDone;

      final source = await context.webDriver.pageSource;
      // Main is re-invoked which shouldn't clear the state.
      expect(source, contains(originalString));
      expect(source, contains(newString));
    });

    test('can send events before and after hot restart', () async {
      final client = context.debugConnection.vmService;
      await client.streamListen('Isolate');

      // The event just before hot restart might never be received,
      // but the injected client continues to work and send events
      // after hot restart.
      final eventsDone = expectLater(
        client.onIsolateEvent,
        emitsThrough(
          _hasKind(
            EventKind.kServiceExtensionAdded,
          ).having((e) => e.extensionRPC, 'service', 'ext.bar'),
        ),
      );

      var vm = await client.getVM();
      var isolateId = vm.isolates!.first.id!;
      var isolate = await client.getIsolate(isolateId);
      var library = isolate.rootLib!.uri!;

      final callback = '(_, __) async => ServiceExtensionResponse.result("")';

      await client.evaluate(
        isolateId,
        library,
        "registerExtension('ext.foo', $callback)",
      );

      await recompile();
      final mainDone = waitForMainToExecute();
      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      expect(
        await fakeClient.callServiceExtension(hotRestart!),
        const TypeMatcher<Success>(),
      );

      vm = await client.getVM();
      isolateId = vm.isolates!.first.id!;
      isolate = await client.getIsolate(isolateId);
      library = isolate.rootLib!.uri!;

      await client.evaluate(
        isolateId,
        library,
        "registerExtension('ext.bar', $callback)",
      );

      await eventsDone;
      await mainDone;

      final source = await context.webDriver.pageSource;
      // Main is re-invoked which shouldn't clear the state.
      expect(source, contains('Hello World!'));
    });

    test('can refresh the page via the fullReload service extension', () async {
      final client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await makeEditAndRecompile();

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
      final mainDone = waitForMainToExecute();
      final fullReload = context.getRegisteredServiceExtension('fullReload');
      expect(
        await fakeClient.callServiceExtension(fullReload!),
        isA<Success>(),
      );

      await eventsDone;
      await mainDone;

      final source = await context.webDriver.pageSource;
      // Should see only the new text
      expect(source.contains(originalString), isFalse);
      expect(source.contains(newString), isTrue);
    });

    test('can hot restart while paused', () async {
      final client = context.debugConnection.vmService;
      var vm = await client.getVM();
      var isolateId = vm.isolates!.first.id!;
      await client.streamListen('Debug');
      final stream = client.onEvent('Debug');
      final scriptList = await client.getScripts(isolateId);
      final main = scriptList.scripts!.firstWhere(
        (script) => script.uri!.contains('main.dart'),
      );
      final bpLine = await context.findBreakpointLine(
        'printCount',
        isolateId,
        main,
      );
      await client.addBreakpoint(isolateId, main.id!, bpLine);
      await stream.firstWhere(
        (event) => event.kind == EventKind.kPauseBreakpoint,
      );

      await makeEditAndRecompile();
      final mainDone = waitForMainToExecute();
      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      await fakeClient.callServiceExtension(hotRestart!);

      await mainDone;

      final source = await context.webDriver.pageSource;

      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains(originalString), isTrue);
      expect(source.contains(newString), isTrue);

      vm = await client.getVM();
      isolateId = vm.isolates!.first.id!;
      final isolate = await client.getIsolate(isolateId);

      // Previous breakpoint should be cleared.
      expect(isolate.breakpoints!.isEmpty, isTrue);
    });

    test('can evaluate expressions after hot restart', () async {
      final client = context.debugConnection.vmService;

      await recompile();
      final hotRestart = context.getRegisteredServiceExtension('hotRestart');
      await fakeClient.callServiceExtension(hotRestart!);

      final vm = await client.getVM();
      final isolateId = vm.isolates!.first.id!;
      final isolate = await client.getIsolate(isolateId);
      final library = isolate.rootLib!.uri!;

      // Expression evaluation while running should work.
      final result = await client.evaluate(isolateId, library, 'true');
      expect(
        result,
        isA<InstanceRef>().having(
          (instance) => instance.valueAsString,
          'valueAsString',
          'true',
        ),
      );
    });
  }, timeout: Timeout.factor(2));

  group(
    'Injected client with hot restart',
    () {
      group('and with debugging', () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              reloadConfiguration: ReloadConfiguration.hotRestart,
              compilationMode: compilationMode,
              moduleFormat: provider.ddcModuleFormat,
              canaryFeatures: provider.canaryFeatures,
            ),
          );
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can hot restart changes ', () async {
          final mainDone = waitForMainToExecute();
          await makeEditAndRecompile();
          await mainDone;
          final source = await context.webDriver.pageSource;

          // Main is re-invoked which shouldn't clear the state.
          expect(source.contains(originalString), isTrue);
          expect(source.contains(newString), isTrue);
          // The ext.flutter.disassemble callback is invoked and waited for.
          expect(
            source,
            contains('start disassemble end disassemble $newString'),
          );
        });

        test(
          'fires isolate create/destroy events during hot restart',
          () async {
            final client = context.debugConnection.vmService;
            await client.streamListen('Isolate');

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

            await makeEditAndRecompile();

            await eventsDone;
          },
        );
      });

      group('and without debugging', () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              reloadConfiguration: ReloadConfiguration.hotRestart,
              compilationMode: compilationMode,
              moduleFormat: provider.ddcModuleFormat,
              canaryFeatures: provider.canaryFeatures,
            ),
            debugSettings: TestDebugSettings.noDevTools().copyWith(
              enableDebugging: false,
            ),
          );
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can hot restart changes ', () async {
          final mainDone = waitForMainToExecute(debuggingEnabled: false);
          await makeEditAndRecompile();
          await mainDone;
          final source = await context.webDriver.pageSource;

          // Main is re-invoked which shouldn't clear the state.
          expect(source.contains(originalString), isTrue);
          expect(source.contains(newString), isTrue);
          // The ext.flutter.disassemble callback is invoked and waited for.
          expect(
            source,
            contains('start disassemble end disassemble $newString'),
          );
        });
      });
    },
    // `BuildResult`s are only ever emitted when using the build daemon.
    skip: compilationMode != CompilationMode.buildDaemon,
    timeout: Timeout.factor(2),
  );

  group('when isolates_paused_on_start is true', () {
    late VmService client;
    late VmService fakeClient;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          compilationMode: compilationMode,
          moduleFormat: provider.ddcModuleFormat,
          canaryFeatures: provider.canaryFeatures,
        ),
      );
      client = context.debugConnection.vmService;
      fakeClient = await context.connectFakeClient();
      await client.setFlag('pause_isolates_on_start', 'true');
      await client.streamListen('Isolate');
    });

    tearDown(() async {
      await context.tearDown();
    });

    test(
      'after hot-restart, does not run app until there is a resume event',
      () async {
        await makeEditAndRecompile();

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

        final mainDone = waitForMainToExecute();
        final hotRestart = context.getRegisteredServiceExtension('hotRestart');
        expect(
          await fakeClient.callServiceExtension(hotRestart!),
          const TypeMatcher<Success>(),
        );

        await eventsDone;

        final sourceBeforeResume = await context.webDriver.pageSource;
        expect(sourceBeforeResume.contains(newString), isFalse);

        final vm = await client.getVM();
        final isolateId = vm.isolates!.first.id!;
        await client.resume(isolateId);

        await mainDone;

        final sourceAfterResume = await context.webDriver.pageSource;
        expect(sourceAfterResume.contains(newString), isTrue);
      },
    );

    test(
      'after page refresh, does not run app until there is a resume event',
      () async {
        final mainDone = waitForMainToExecute();
        await makeEditAndRecompile();
        await context.webDriver.driver.refresh();

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

        await eventsDone;

        final sourceBeforeResume = await context.webDriver.pageSource;
        expect(sourceBeforeResume.contains(newString), isFalse);

        final vm = await client.getVM();
        final isolateId = vm.isolates!.first.id!;
        await client.resume(isolateId);

        await mainDone;

        final sourceAfterResume = await context.webDriver.pageSource;
        expect(sourceAfterResume.contains(newString), isTrue);
      },
    );
  });
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
