// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'dart:io';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
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
const _testItems = <String, bool>{
  'main.dart.js': null,
  'main.dart.bootstrap.js': true,
  'main.unsound.ddc.js': true,
};

void main() {
  String exampleDirectory;
  String soundExampleDirectory;
  setUpAll(() async {
    exampleDirectory =
        p.absolute(p.join(p.current, '..', 'fixtures', '_webdevSmoke'));
    soundExampleDirectory =
        p.absolute(p.join(p.current, '..', 'fixtures', '_webdevSoundSmoke'));

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);

    process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: soundExampleDirectory,
        environment: getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
  });

  test('smoke test is configured properly', () async {
    var smokeYaml =
        loadYaml(await File('$exampleDirectory/pubspec.yaml').readAsString())
            as YamlMap;
    var webdevYaml =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(smokeYaml['environment']['sdk'],
        equals(webdevYaml['environment']['sdk']));
    expect(smokeYaml['dev_dependencies']['build_runner'],
        equals(buildRunnerConstraint.toString()));
    expect(smokeYaml['dev_dependencies']['build_web_compilers'],
        equals(buildWebCompilersContraint.toString()));
  });

  test('build should fail if targetting an existing directory', () async {
    await d.file('simple thing', 'throw-away').create();

    var args = ['build', '-o', 'web:${d.sandbox}'];

    var process = await runWebDev(args, workingDirectory: exampleDirectory);

    // NOTE: We'd like this to be more useful
    // See https://github.com/dart-lang/build/issues/1283

    await expectLater(
        process.stdout,
        emitsThrough(
            contains('Unable to create merged directory at ${d.sandbox}.')));
    await expectLater(
        process.stdout,
        emitsThrough(
            'Choose a different directory or delete the contents of that '
            'directory.'));

    await process.shouldExit(isNot(0));
  });

  test('build should allow passing extra arguments to build_runner', () async {
    var args = [
      'build',
      '-o',
      'web:${d.sandbox}',
      '--',
      '--delete-conflicting-outputs'
    ];

    var process = await runWebDev(args, workingDirectory: exampleDirectory);

    await checkProcessStdout(process, ['Succeeded']);
    await process.shouldExit(0);
  });

  group('should build with valid configuration', () {
    for (var withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var args = ['build', '-o', 'web:${d.sandbox}'];
        if (withDDC) {
          args.add('--no-release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var expectedItems = <Object>['Succeeded'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        for (var entry in _testItems.entries) {
          var shouldExist = (entry.value ?? withDDC) == withDDC;

          if (shouldExist) {
            await d.file(entry.key, isNotEmpty).validate();
          } else {
            await d.nothing(entry.key).validate();
          }
        }
      });
    }
    test(
      'and --sound-null-safety',
      () async {
        var args = [
          'build',
          '-o',
          'web:${d.sandbox}',
          '--no-release',
          '--sound-null-safety'
        ];

        var process =
            await runWebDev(args, workingDirectory: soundExampleDirectory);

        var expectedItems = <Object>['Succeeded'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.file('main.sound.ddc.js', isNotEmpty).validate();
      },
      skip: semver.Version.parse(Platform.version.split(' ').first) >
              semver.Version.parse('2.11.0')
          ? null
          : 'SDK does not support sound null safety',
    );

    test(
      'and --no-sound-null-safety',
      () async {
        var args = [
          'build',
          '-o',
          'web:${d.sandbox}',
          '--no-release',
          '--no-sound-null-safety'
        ];

        var process =
            await runWebDev(args, workingDirectory: soundExampleDirectory);

        var expectedItems = <Object>['Succeeded'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.file('main.unsound.ddc.js', isNotEmpty).validate();
      },
      skip: semver.Version.parse(Platform.version.split(' ').first) >
              semver.Version.parse('2.11.0')
          ? null
          : 'SDK does not support sound null safety',
    );
  });

  group('should build with --output=NONE', () {
    for (var withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var args = ['build', '--output=NONE'];
        if (withDDC) {
          args.add('--no-release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var expectedItems = <Object>['Succeeded'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.nothing('build').validate(exampleDirectory);
      });
    }
  });

  group('should serve with valid configuration', () {
    for (var withDDC in [true, false]) {
      var type = withDDC ? 'DDC' : 'dart2js';
      test('using $type', () async {
        var openPort = await findUnusedPort();
        var args = ['serve', 'web:$openPort'];
        if (!withDDC) {
          args.add('--release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var hostUrl = 'http://localhost:$openPort';

        // Wait for the initial build to finish.
        await expectLater(process.stdout, emitsThrough(contains('Succeeded')));

        var client = HttpClient();

        try {
          for (var entry in _testItems.entries) {
            var url = Uri.parse('$hostUrl/${entry.key}');

            var request = await client.getUrl(url);
            var response = await request.close();

            var shouldExist = (entry.value ?? withDDC) == withDDC;

            expect(response.statusCode, shouldExist ? 200 : 404,
                reason: 'Expecting "$url"? $shouldExist');
          }
        } finally {
          client.close(force: true);
        }

        await process.kill();
        await process.shouldExit();
      });
    }
  });

  group('Should fail with invalid build directories', () {
    var invalidServeDirs = ['.', '../', '../foo', 'foo/bar', 'foo/../'];
    for (var dir in invalidServeDirs) {
      for (var command in ['build', 'serve']) {
        test('cannot $command directory: `$dir`', () async {
          var args = [
            command,
            if (command == 'build') '--output=$dir:foo' else dir
          ];

          var process =
              await runWebDev(args, workingDirectory: exampleDirectory);
          await expectLater(
              process.stdout,
              emitsThrough(contains(
                  'Invalid configuration: Only top level directories under the '
                  'package can be built')));
          await expectLater(process.exitCode, completion(ExitCode.config.code));
        });
      }
    }
  });

  group('should work with expression evaluation', () {
    test('enabled', () async {
      var openPort = await findUnusedPort();
      // running daemon command that starts dwds without keyboard input
      var args = [
        'daemon',
        'web:$openPort',
        '--enable-expression-evaluation',
        '--verbose',
      ];
      var process = await runWebDev(args, workingDirectory: exampleDirectory);
      VmService vmService;

      try {
        // Wait for debug service Uri
        String wsUri;
        await expectLater(process.stdout, emitsThrough((message) {
          wsUri = getDebugServiceUri(message as String);
          return wsUri != null;
        }));
        expect(wsUri, isNotNull);

        vmService = await vmServiceConnectUri(wsUri);
        var vm = await vmService.getVM();
        var isolate = vm.isolates.first;
        var scripts = await vmService.getScripts(isolate.id);

        await vmService.streamListen('Debug');
        var stream = vmService.onEvent('Debug');

        var mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));

        var bpLine = await findBreakpointLine(
            vmService, 'printCounter', isolate.id, mainScript);

        var bp = await vmService.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, bpLine);
        expect(bp, isNotNull);

        await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        var result = await vmService.evaluateInFrame(isolate.id, 0, 'true');
        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', 'true'));
      } finally {
        await vmService?.dispose();
        await exitWebdev(process);
        await process.shouldExit();
      }
    }, timeout: const Timeout.factor(2));

    test('disabled', () async {
      var openPort = await findUnusedPort();
      var args = [
        'daemon',
        'web:$openPort',
        '--no-enable-expression-evaluation',
      ];
      var process = await runWebDev(args, workingDirectory: exampleDirectory);
      VmService vmService;

      try {
        // Wait for debug service Uri
        String wsUri;
        await expectLater(process.stdout, emitsThrough((message) {
          wsUri = getDebugServiceUri(message as String);
          return wsUri != null;
        }));
        expect(wsUri, isNotNull);

        vmService = await vmServiceConnectUri(wsUri);
        var vm = await vmService.getVM();
        var isolate = vm.isolates.first;
        var scripts = await vmService.getScripts(isolate.id);

        await vmService.streamListen('Debug');
        var stream = vmService.onEvent('Debug');

        var mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));

        var bpLine = await findBreakpointLine(
            vmService, 'printCounter', isolate.id, mainScript);

        var bp = await vmService.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, bpLine);
        expect(bp, isNotNull);

        var event = await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        expect(
            () => vmService.evaluateInFrame(
                isolate.id, event.topFrame.index, 'true'),
            throwsRPCError);
      } finally {
        await vmService?.dispose();
        await exitWebdev(process);
        await process.shouldExit();
      }
    });
  }, tags: 'expression-compilation-service');
}
