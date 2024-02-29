// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 10))

import 'package:dwds/dwds.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

const originalString = 'Hello World!';
const newString = 'Bonjour le monde!';

void main() {
  // set to true for debug logging.
  final debug = false;

  final provider = TestSdkConfigurationProvider(verbose: debug);
  tearDownAll(provider.dispose);

  final context =
      TestContext(TestProject.testAppendBodyWithSoundNullSafety, provider);

  Future<void> makeEditAndWaitForRebuild() async {
    context.makeEditToDartEntryFile(
      toReplace: originalString,
      replaceWith: newString,
    );
    await context.waitForSuccessfulBuild(propagateToBrowser: true);
  }

  void undoEdit() {
    context.makeEditToDartEntryFile(
      toReplace: newString,
      replaceWith: originalString,
    );
  }

  for (final isInternalApp in [true, false]) {
    group(
      '${isInternalApp ? 'Internal' : 'External'} app | Injected client with live reload',
      () {
        group('and with debugging', () {
          setUp(() async {
            setCurrentLogWriter(debug: debug);
            await context.setUp(
              testSettings: TestSettings(
                reloadConfiguration: ReloadConfiguration.liveReload,
              ),
              appMetadata: isInternalApp
                  ? TestAppMetadata.internalApp()
                  : TestAppMetadata.externalApp(),
            );
          });

          tearDown(() async {
            undoEdit();
            await context.tearDown();
          });

          test('can live reload changes ', () async {
            await makeEditAndWaitForRebuild();
            final source = await context.webDriver.pageSource;

            _sourceIsExpected(source, isFullReload: true);
          });
        });

        group('and without debugging', () {
          setUp(() async {
            setCurrentLogWriter(debug: debug);
            await context.setUp(
              testSettings: TestSettings(
                reloadConfiguration: ReloadConfiguration.liveReload,
              ),
              debugSettings: TestDebugSettings.noDevTools().copyWith(
                enableDebugging: false,
              ),
            );
          });

          tearDown(() async {
            undoEdit();
            await context.tearDown();
          });

          test('can live reload changes ', () async {
            await makeEditAndWaitForRebuild();

            final source = await context.webDriver.pageSource;

            _sourceIsExpected(source, isFullReload: true);
          });
        });

        group('and without debugging using WebSockets', () {
          setUp(() async {
            setCurrentLogWriter(debug: debug);
            await context.setUp(
              testSettings: TestSettings(
                reloadConfiguration: ReloadConfiguration.liveReload,
              ),
              debugSettings: TestDebugSettings.noDevTools().copyWith(
                enableDebugging: false,
                useSse: false,
              ),
            );
          });

          tearDown(() async {
            await context.tearDown();
            undoEdit();
          });

          test('can live reload changes ', () async {
            await makeEditAndWaitForRebuild();

            final source = await context.webDriver.pageSource;

            _sourceIsExpected(source, isFullReload: true);
          });
        });
      },
      timeout: Timeout.factor(2),
    );

    group(
      '${isInternalApp ? 'Internal' : 'External'} app | Injected client',
      () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              enableExpressionEvaluation: true,
            ),
          );
        });

        tearDown(() async {
          await context.tearDown();
          undoEdit();
        });

        test('destroys and recreates the isolate during a hot restart',
            () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');
          await makeEditAndWaitForRebuild();

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: !isInternalApp,
          );

          expect(
            await client.callServiceExtension('hotRestart'),
            const TypeMatcher<Success>(),
          );

          await restartComplete;
        });

        test('can execute simultaneous hot restarts', () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');
          await makeEditAndWaitForRebuild();

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: !isInternalApp,
          );

          // Execute two hot restart calls in parallel.
          final done = Future.wait([
            client.callServiceExtension('hotRestart'),
            client.callServiceExtension('hotRestart'),
          ]);
          expect(
            await done,
            [const TypeMatcher<Success>(), const TypeMatcher<Success>()],
          );

          await restartComplete;

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
        });

        test('destroys and recreates the isolate during a page refresh',
            () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');
          await makeEditAndWaitForRebuild();

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: true,
          );

          await context.webDriver.driver.refresh();

          await restartComplete;
        });

        test('can hot restart via the service extension', () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');
          await makeEditAndWaitForRebuild();

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: !isInternalApp,
          );

          expect(
            await client.callServiceExtension('hotRestart'),
            const TypeMatcher<Success>(),
          );
          print('waiting for restart complete');
          await restartComplete;
          print('done waiting for restart complete');

          final source = await context.webDriver.pageSource;
          _sourceIsExpected(source, isFullReload: !isInternalApp);
        });

        test('can send events before and after hot restart', () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');

          // The event just before hot restart might never be received,
          // but the injected client continues to work and send events
          // after hot restart.
          final eventReceived = expectLater(
            client.onIsolateEvent,
            emitsThrough(
              _hasKind(EventKind.kServiceExtensionAdded)
                  .having((e) => e.extensionRPC, 'service', 'ext.bar'),
            ),
          );

          var vm = await client.getVM();
          var isolateId = vm.isolates!.first.id!;
          var isolate = await client.getIsolate(isolateId);
          var library = isolate.rootLib!.uri!;

          final String callback =
              '(_, __) async => ServiceExtensionResponse.result("")';

          await client.evaluate(
            isolateId,
            library,
            "registerExtension('ext.foo', $callback)",
          );

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: !isInternalApp,
          );

          expect(
            await client.callServiceExtension('hotRestart'),
            const TypeMatcher<Success>(),
          );

          await restartComplete;

          vm = await client.getVM();
          isolateId = vm.isolates!.first.id!;
          isolate = await client.getIsolate(isolateId);
          library = isolate.rootLib!.uri!;

          await client.evaluate(
            isolateId,
            library,
            "registerExtension('ext.bar', $callback)",
          );

          await eventReceived;

          final source = await context.webDriver.pageSource;
          _sourceIsExpected(source, isFullReload: !isInternalApp);
        });

        test('can refresh the page via the fullReload service extension',
            () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');
          await makeEditAndWaitForRebuild();

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: true,
          );

          expect(
              await client.callServiceExtension('fullReload'), isA<Success>());

          await restartComplete;

          final source = await context.webDriver.pageSource;
          _sourceIsExpected(source, isFullReload: true);
        });

        test('can hot restart while paused', () async {
          final client = context.debugConnection.vmService;
          var vm = await client.getVM();
          var isolateId = vm.isolates!.first.id!;
          await client.streamListen('Isolate');
          await client.streamListen('Debug');
          final stream = client.onEvent('Debug');
          final scriptList = await client.getScripts(isolateId);
          final main = scriptList.scripts!
              .firstWhere((script) => script.uri!.contains('main.dart'));
          final bpLine =
              await context.findBreakpointLine('printCount', isolateId, main);
          await client.addBreakpoint(isolateId, main.id!, bpLine);
          await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          await makeEditAndWaitForRebuild();

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: !isInternalApp,
          );

          expect(
            await client.callServiceExtension('hotRestart'),
            const TypeMatcher<Success>(),
          );

          await restartComplete;

          final source = await context.webDriver.pageSource;

          // Hot-restart triggers a full reload which clears the state.
          _sourceIsExpected(source, isFullReload: !isInternalApp);

          vm = await client.getVM();
          isolateId = vm.isolates!.first.id!;
          final isolate = await client.getIsolate(isolateId);

          // Previous breakpoint should be cleared.
          expect(isolate.breakpoints!.isEmpty, isTrue);
        });

        test('can evaluate expressions after hot restart', () async {
          final client = context.debugConnection.vmService;
          await client.streamListen('Isolate');

          final restartComplete = _restartCompleteExpectation(
            isolateEventStream: client.onIsolateEvent,
            isFullReload: !isInternalApp,
          );

          await client.callServiceExtension('hotRestart');

          await restartComplete;

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
      },
      timeout: Timeout.factor(2),
    );

    group(
      '${isInternalApp ? 'Internal' : 'External'} app | Injected client with hot restart',
      () {
        group('and with debugging', () {
          setUp(() async {
            setCurrentLogWriter(debug: debug);
            await context.setUp(
              testSettings: TestSettings(
                reloadConfiguration: ReloadConfiguration.hotRestart,
              ),
            );
          });

          tearDown(() async {
            await context.tearDown();
            undoEdit();
          });

          test('can hot restart changes ', () async {
            await makeEditAndWaitForRebuild();

            final source = await context.webDriver.pageSource;

            _sourceIsExpected(source, isFullReload: !isInternalApp);
          });

          test('fires isolate create/destroy events during hot restart',
              () async {
            final client = context.debugConnection.vmService;
            await client.streamListen('Isolate');

            final restartComplete = _restartCompleteExpectation(
              isolateEventStream: client.onIsolateEvent,
              isFullReload: !isInternalApp,
            );

            await makeEditAndWaitForRebuild();

            await restartComplete;
          });
        });

        group('and without debugging', () {
          setUp(() async {
            setCurrentLogWriter(debug: debug);
            await context.setUp(
              testSettings: TestSettings(
                reloadConfiguration: ReloadConfiguration.hotRestart,
              ),
              debugSettings: TestDebugSettings.noDevTools()
                  .copyWith(enableDebugging: false),
            );
          });

          tearDown(() async {
            await context.tearDown();
            undoEdit();
          });

          test('can hot restart changes ', () async {
            await makeEditAndWaitForRebuild();

            final source = await context.webDriver.pageSource;

            _sourceIsExpected(source, isFullReload: !isInternalApp);
          });
        });
      },
      timeout: Timeout.factor(2),
    );
  }
}

Future _restartCompleteExpectation({
  required Stream<Event> isolateEventStream,
  required bool isFullReload,
}) {
  if (isFullReload) {
    return expectLater(
      isolateEventStream,
      emitsThrough(
        emitsInOrder([
          _hasKind(EventKind.kIsolateExit),
          _hasKind(EventKind.kIsolateStart),
          _hasKind(EventKind.kIsolateRunnable),
        ]),
      ),
    );
  }

  return Future.value(null);
}

void _sourceIsExpected(String source, {required bool isFullReload}) {
  expect(source, contains(newString));
  if (isFullReload) {
    // A full reload clears the state.
    expect(source.contains(originalString), isFalse);
  } else {
    // A hot-restart invokes main which shouldn't clear the state.
    expect(source, contains(originalString));
  }
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
