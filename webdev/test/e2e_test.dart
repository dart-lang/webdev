// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:webdev/src/logging.dart';
import 'package:webdev/src/pubspec.dart';
import 'package:webdev/src/serve/utils.dart';
import 'package:webdev/src/util.dart';
import 'package:yaml/yaml.dart';

import 'daemon/utils.dart';
import 'test_utils.dart';

/// Key: name of file in web directory
/// Value: `null`  - exists in both modes
///        `true`  - DDC only
///        `false` - dart2js only
final _testItems = <String, bool?>{
  'main.dart.js': null,
  'main.dart.bootstrap.js': true,
  'main.ddc.js': true,
};

void main() {
  // Change to true for debugging.
  const debug = false;

  final testRunner = TestRunner();
  late String exampleDirectory;
  setUpAll(() async {
    configureLogWriter(debug);
    await testRunner.setUpAll();
    exampleDirectory = p.absolute(
      p.join(p.current, '..', 'fixtures', '_webdev_smoke'),
    );

    final process = await TestProcess.start(
      dartPath,
      ['pub', 'upgrade'],
      workingDirectory: exampleDirectory,
      environment: getPubEnvironment(),
    );

    await process.shouldExit(0);

    await d
        .file('.dart_tool/package_config.json', isNotEmpty)
        .validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
  });

  tearDownAll(testRunner.tearDownAll);

  test('smoke test is configured properly', () async {
    final smokeYaml =
        loadYaml(await File('$exampleDirectory/pubspec.yaml').readAsString())
            as YamlMap;
    final webdevYaml =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(
      smokeYaml['environment']['sdk'],
      equals(webdevYaml['environment']['sdk']),
    );
    expect(
      buildRunnerConstraint.allowsAny(
        VersionConstraint.parse(smokeYaml['dev_dependencies']['build_runner']),
      ),
      true,
    );
    expect(
      smokeYaml['dev_dependencies']['build_web_compilers'],
      equals(buildWebCompilersConstraint.toString()),
    );
  });

  test('build should fail if targeting an existing directory', () async {
    await d.file('simple thing', 'throw-away').create();

    final args = ['build', '-o', 'web:${d.sandbox}'];

    final process = await testRunner.runWebDev(
      args,
      workingDirectory: exampleDirectory,
    );

    // NOTE: We'd like this to be more useful
    // See https://github.com/dart-lang/build/issues/1283

    await expectLater(
      process.stdout,
      emitsThrough(
        contains(
          'Unable to create merged directory ${d.sandbox}. '
          'Choose a different directory or delete the contents of that '
          'directory.',
        ),
      ),
    );

    await process.shouldExit(isNot(0));
  });

  test(
    'build should allow passing extra arguments to build_runner',
    () async {
      final args = [
        'build',
        '-o',
        'web:${d.sandbox}',
        '--',
        '--delete-conflicting-outputs',
      ];

      final process = await testRunner.runWebDev(
        args,
        workingDirectory: exampleDirectory,
      );

      await checkProcessStdout(process, ['Built with build_runner']);
      await process.shouldExit(0);
    },
    // https://github.com/dart-lang/webdev/issues/2489,
    skip: Platform.isWindows,
  );

  group('should build with valid configuration', () {
    for (final withDDC in [true, false]) {
      test(
        withDDC ? 'DDC' : 'dart2js',
        () async {
          final args = ['build', '-o', 'web:${d.sandbox}'];
          if (withDDC) {
            args.add('--no-release');
          }

          final process = await testRunner.runWebDev(
            args,
            workingDirectory: exampleDirectory,
          );

          final expectedItems = <Object>['Built with build_runner'];

          await checkProcessStdout(process, expectedItems);
          await process.shouldExit(0);

          for (final entry in _testItems.entries) {
            final shouldExist = (entry.value ?? withDDC) == withDDC;

            if (shouldExist) {
              await d.file(entry.key, isNotEmpty).validate();
            } else {
              await d.nothing(entry.key).validate();
            }
          }
        },
        // https://github.com/dart-lang/webdev/issues/2489
        skip: Platform.isWindows,
      );
    }
    test(
      'and --null-safety=sound',
      () async {
        final args = [
          'build',
          '-o',
          'web:${d.sandbox}',
          '--no-release',
          '--null-safety=sound',
        ];

        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );

        final expectedItems = <Object>['Built with build_runner'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.file('main.ddc.js', isNotEmpty).validate();
      },
      // https://github.com/dart-lang/webdev/issues/2489
      skip: Platform.isWindows,
    );
  });

  group('should build with --output=NONE', () {
    for (final withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        final args = ['build', '--output=NONE'];
        if (withDDC) {
          args.add('--no-release');
        }

        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );

        final expectedItems = <Object>['Built with build_runner'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.nothing('build').validate(exampleDirectory);
      });
    }
  });

  group('should serve with valid configuration', () {
    for (final withDDC in [true, false]) {
      final type = withDDC ? 'DDC' : 'dart2js';
      test('using $type', () async {
        final openPort = await findUnusedPort();
        final args = ['serve', 'web:$openPort'];
        if (!withDDC) {
          args.add('--release');
        }

        final stdoutDone = Completer<void>();
        final stderrDone = Completer<void>();
        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );
        process.stdoutStream().listen((_) => {}, onDone: stdoutDone.complete);
        process.stderrStream().listen((_) => {}, onDone: stderrDone.complete);

        final hostUrl = 'http://localhost:$openPort';

        // Wait for the initial build to finish.
        await expectLater(
          process.stdout,
          emitsThrough(contains('Built with build_runner')),
        );

        final client = HttpClient();

        try {
          for (final entry in _testItems.entries) {
            final url = Uri.parse('$hostUrl/${entry.key}');

            final request = await client.getUrl(url);
            final response = await request.close();

            final shouldExist = (entry.value ?? withDDC) == withDDC;

            expect(
              response.statusCode,
              shouldExist ? 200 : 404,
              reason: 'Expecting "$url"? $shouldExist',
            );
          }
        } finally {
          client.close(force: true);
        }

        await process.kill();
        await process.shouldExit();
        await Future.wait([stdoutDone.future, stderrDone.future]);
      });
    }
  });

  group('Should fail with invalid build directories', () {
    final invalidServeDirs = ['.', '../', '../foo', 'foo/bar', 'foo/../'];
    for (final dir in invalidServeDirs) {
      for (final command in ['build', 'serve']) {
        test('cannot $command directory: `$dir`', () async {
          final args = [
            command,
            if (command == 'build') '--output=$dir:foo' else dir,
          ];

          final process = await testRunner.runWebDev(
            args,
            workingDirectory: exampleDirectory,
          );
          await expectLater(
            process.stdout,
            emitsThrough(
              contains(
                'Invalid configuration: Only top level directories under the '
                'package can be built',
              ),
            ),
          );
          await expectLater(process.exitCode, completion(ExitCode.config.code));
        });
      }
    }
  });

  group('should work with ', () {
    setUp(() async {
      configureLogWriter(debug);
    });
    group('and --enable-expression-evaluation:', () {
      setUp(() async {
        configureLogWriter(debug);
      });
      test('evaluateInFrame', () async {
        final openPort = await findUnusedPort();
        // running daemon command that starts dwds without keyboard input
        final args = [
          'daemon',
          'web:$openPort',
          '--enable-expression-evaluation',
          '--null-safety=sound',
          '--verbose',
        ];
        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );
        VmService? vmService;

        process.stdoutStream().listen(Logger.root.fine);
        process.stderrStream().listen(Logger.root.warning);

        try {
          // Wait for debug service Uri
          String? wsUri;
          await expectLater(
            process.stdout,
            emitsThrough((message) {
              wsUri = getDebugServiceUri(message as String);
              return wsUri != null;
            }),
          );
          Logger.root.fine('vm service uri: $wsUri');
          expect(wsUri, isNotNull);

          vmService = await vmServiceConnectUri(wsUri!);
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final scripts = await vmService.getScripts(isolateId);

          await vmService.streamListen('Debug');
          final stream = vmService.onEvent('Debug');

          final mainScript = scripts.scripts!.firstWhere(
            (each) => each.uri!.contains('main.dart'),
          );

          final bpLine = await findBreakpointLine(
            vmService,
            'printCounter',
            isolateId,
            mainScript,
          );

          final bp = await vmService.addBreakpointWithScriptUri(
            isolateId,
            mainScript.uri!,
            bpLine,
          );
          expect(bp, isNotNull);

          await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint,
          );

          final expression =
              '() { const sound = !(<Null>[] is List<int>); return sound; } ()';
          final result = await vmService.evaluateInFrame(
            isolateId,
            0,
            expression,
          );

          expect(
            result,
            const TypeMatcher<InstanceRef>().having(
              (instance) => instance.valueAsString,
              'valueAsString',
              'true',
            ),
          );
        } finally {
          await vmService?.dispose();
          await exitWebdev(process);
          await process.shouldExit();
        }
      }, timeout: const Timeout.factor(2));

      test('evaluate', () async {
        final openPort = await findUnusedPort();
        // running daemon command that starts dwds without keyboard input
        final args = [
          'daemon',
          'web:$openPort',
          '--enable-expression-evaluation',
          '--verbose',
        ];
        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );

        process.stdoutStream().listen(Logger.root.fine);
        process.stderrStream().listen(Logger.root.warning);

        VmService? vmService;

        try {
          // Wait for debug service Uri
          String? wsUri;
          await expectLater(
            process.stdout,
            emitsThrough((message) {
              wsUri = getDebugServiceUri(message as String);
              return wsUri != null;
            }),
          );
          expect(wsUri, isNotNull);

          vmService = await vmServiceConnectUri(wsUri!);
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final isolate = await vmService.getIsolate(isolateId);
          final libraryId = isolate.rootLib!.id!;

          await vmService.streamListen('Debug');

          var result = await vmService.evaluate(
            isolateId,
            libraryId,
            '(document?.body?.children?.first as SpanElement)?.text',
          );

          expect(
            result,
            const TypeMatcher<InstanceRef>().having(
              (instance) => instance.valueAsString,
              'valueAsString',
              'Hello World!!',
            ),
          );

          result = await vmService.evaluate(
            isolateId,
            libraryId,
            'topLevelMethod()',
          );

          expect(
            result,
            const TypeMatcher<InstanceRef>().having(
              (instance) => instance.valueAsString,
              'valueAsString',
              equals('verify this!'),
            ),
          );
        } finally {
          await vmService?.dispose();
          await exitWebdev(process);
          await process.shouldExit();
        }
      }, timeout: const Timeout.factor(2));

      test('evaluate and get objects', () async {
        final openPort = await findUnusedPort();
        // running daemon command that starts dwds without keyboard input
        final args = [
          'daemon',
          'web:$openPort',
          '--enable-expression-evaluation',
          '--verbose',
        ];
        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );

        process.stdoutStream().listen(Logger.root.fine);
        process.stderrStream().listen(Logger.root.warning);

        VmService? vmService;

        try {
          // Wait for debug service Uri
          String? wsUri;
          await expectLater(
            process.stdout,
            emitsThrough((message) {
              wsUri = getDebugServiceUri(message as String);
              return wsUri != null;
            }),
          );
          expect(wsUri, isNotNull);

          vmService = await vmServiceConnectUri(wsUri!);
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final isolate = await vmService.getIsolate(isolateId);
          final libraryId = isolate.rootLib!.id!;

          await vmService.streamListen('Debug');

          final result = await vmService.evaluate(
            isolateId,
            libraryId,
            '[true, false]',
          );
          expect(
            result,
            const TypeMatcher<InstanceRef>().having(
              (instance) => instance.classRef?.name,
              'class name',
              'JSArray<bool>',
            ),
          );

          final instanceRef = result as InstanceRef;
          final list = await vmService.getObject(isolateId, instanceRef.id!);
          expect(
            list,
            const TypeMatcher<Instance>().having(
              (instance) => instance.classRef?.name,
              'class name',
              'JSArray<bool>',
            ),
          );

          final elements = (list as Instance).elements;
          expect(elements, [
            const TypeMatcher<InstanceRef>().having(
              (instance) => instance.valueAsString,
              'value',
              'true',
            ),
            const TypeMatcher<InstanceRef>().having(
              (instance) => instance.valueAsString,
              'value',
              'false',
            ),
          ]);
        } finally {
          await vmService?.dispose();
          await exitWebdev(process);
          await process.shouldExit();
        }
      }, timeout: const Timeout.factor(2));
    });

    group('and --no-enable-expression-evaluation:', () {
      test('evaluateInFrame', () async {
        final openPort = await findUnusedPort();
        final args = [
          'daemon',
          'web:$openPort',
          '--no-enable-expression-evaluation',
          '--verbose',
        ];
        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );
        VmService? vmService;

        try {
          // Wait for debug service Uri
          String? wsUri;
          await expectLater(
            process.stdout,
            emitsThrough((message) {
              wsUri = getDebugServiceUri(message as String);
              return wsUri != null;
            }),
          );
          expect(wsUri, isNotNull);

          vmService = await vmServiceConnectUri(wsUri!);
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final scripts = await vmService.getScripts(isolateId);

          await vmService.streamListen('Debug');
          final stream = vmService.onEvent('Debug');

          final mainScript = scripts.scripts!.firstWhere(
            (each) => each.uri!.contains('main.dart'),
          );

          final bpLine = await findBreakpointLine(
            vmService,
            'printCounter',
            isolateId,
            mainScript,
          );

          final bp = await vmService.addBreakpointWithScriptUri(
            isolateId,
            mainScript.uri!,
            bpLine,
          );
          expect(bp, isNotNull);

          final event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint,
          );

          expect(
            () => vmService!.evaluateInFrame(
              isolateId,
              event.topFrame!.index!,
              'true',
            ),
            throwsRPCError,
          );
        } finally {
          await vmService?.dispose();
          await exitWebdev(process);
          await process.shouldExit();
        }
      });

      test('evaluate', () async {
        final openPort = await findUnusedPort();
        // running daemon command that starts dwds without keyboard input
        final args = [
          'daemon',
          'web:$openPort',
          '--no-enable-expression-evaluation',
          '--verbose',
        ];
        final process = await testRunner.runWebDev(
          args,
          workingDirectory: exampleDirectory,
        );
        VmService? vmService;

        try {
          // Wait for debug service Uri
          String? wsUri;
          await expectLater(
            process.stdout,
            emitsThrough((message) {
              wsUri = getDebugServiceUri(message as String);
              return wsUri != null;
            }),
          );
          expect(wsUri, isNotNull);

          vmService = await vmServiceConnectUri(wsUri!);
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final isolate = await vmService.getIsolate(isolateId);
          final libraryId = isolate.rootLib!.id!;

          await vmService.streamListen('Debug');

          expect(
            () => vmService!.evaluate(isolateId, libraryId, 'topLevelMethod()'),
            throwsRPCError,
          );
        } finally {
          await vmService?.dispose();
          await exitWebdev(process);
          await process.shouldExit();
        }
      }, timeout: const Timeout.factor(2));
    });
  });
}
