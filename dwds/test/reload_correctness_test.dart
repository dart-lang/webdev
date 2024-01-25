// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
import 'package:dwds/dwds.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/utilities.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

const originalString = 'variableToModifyToForceRecompile = 23';
const newString = 'variableToModifyToForceRecompile = 45';

const constantSuccessString = 'ConstantEqualitySuccess';
const constantFailureString = 'ConstantEqualityFailure';

void main() {
  // set to true for debug logging.
  final debug = false;

  final provider = TestSdkConfigurationProvider(verbose: debug);
  tearDownAll(provider.dispose);

  final testHotRestart2 = TestProject.testHotRestart2;
  final context = TestContext(testHotRestart2, provider);

  Future<void> makeEditAndWaitForRebuild() async {
    context.makeEditToDartLibFile(
      libFileName: 'library2.dart',
      toReplace: originalString,
      replaceWith: newString,
    );
    await context.waitForSuccessfulBuild(propagateToBrowser: true);
  }

  void undoEdit() {
    context.makeEditToDartLibFile(
      libFileName: 'library2.dart',
      toReplace: newString,
      replaceWith: originalString,
    );
  }

  group(
    'Injected client',
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

      test(
          'properly compares constants after hot restart via the service extension',
          () async {
        final client = context.debugConnection.vmService;
        await client.streamListen('Isolate');

        var source = await context.webDriver.pageSource;
        expect(
          source,
          contains(
            'ConstObject(reloadVariable: 23, ConstantEqualitySuccess)',
          ),
        );

        await makeEditAndWaitForRebuild();

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

        expect(
          await client.callServiceExtension('hotRestart'),
          const TypeMatcher<Success>(),
        );

        await eventsDone;

        source = await context.webDriver.pageSource;
        if (dartSdkIsAtLeast('3.4.0-61.0.dev')) {
          expect(
            source,
            contains(
              'ConstObject(reloadVariable: 45, ConstantEqualitySuccess)',
            ),
          );
        }
      });
    },
    timeout: Timeout.factor(2),
  );

  group(
    'Injected client with hot restart',
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

        test('properly compares constants after hot restart', () async {
          var source = await context.webDriver.pageSource;
          expect(
            source,
            contains(
              'ConstObject(reloadVariable: 23, ConstantEqualitySuccess)',
            ),
          );

          await makeEditAndWaitForRebuild();

          source = await context.webDriver.pageSource;
          if (dartSdkIsAtLeast('3.4.0-61.0.dev')) {
            expect(
              source,
              contains(
                'ConstObject(reloadVariable: 45, ConstantEqualitySuccess)',
              ),
            );
          }
        });
      });

      group('and without debugging', () {
        setUp(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            testSettings: TestSettings(
              reloadConfiguration: ReloadConfiguration.hotRestart,
            ),
            debugSettings:
                TestDebugSettings.noDevTools().copyWith(enableDebugging: false),
          );
        });

        tearDown(() async {
          await context.tearDown();
          undoEdit();
        });

        test('properly compares constants after hot restart', () async {
          var source = await context.webDriver.pageSource;
          expect(
            source,
            contains(
              'ConstObject(reloadVariable: 23, ConstantEqualitySuccess)',
            ),
          );

          await makeEditAndWaitForRebuild();

          source = await context.webDriver.pageSource;
          if (dartSdkIsAtLeast('3.4.0-61.0.dev')) {
            expect(
              source,
              contains(
                'ConstObject(reloadVariable: 45, ConstantEqualitySuccess)',
              ),
            );
          }
        });
      });
    },
    timeout: Timeout.factor(2),
  );
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
