// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@TestOn('vm')
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test/test.dart';
import 'package:vm_service/vm_service_io.dart';

import 'package:frontend_server_client/frontend_server_client.dart';

void main() async {
  FrontendServerClient client;
  PackageConfig packageConfig;
  String packageRoot;

  setUp(() async {
    await d.dir('a', [
      d.file('pubspec.yaml', '''
name: a
dependencies:
  path: ^1.0.0
      '''),
      d.dir('bin', [
        d.file('main.dart', '''
import 'package:path/path.dart' as p;

void main() async {
  print(message);
  /// Runs in a loop until it is hot reloaded with a new message.
  while (!message.contains('goodbye')) {
    await Future.delayed(const Duration(seconds: 1));
  }
  print(message);
}

String get message => p.join('hello', 'world');

''')
      ]),
    ]).create();
    packageRoot = p.join(d.sandbox, 'a');
    await Process.run(pubExecutable, ['get'], workingDirectory: packageRoot);
    packageConfig = await findPackageConfig(Directory(packageRoot));
  });

  tearDown(() async {
    await client.shutdown();
  });

  test('can compile, recompile, and hot reload a vm app', () async {
    var entrypoint = p.join(packageRoot, 'bin', 'main.dart');
    client = await FrontendServerClient.start(
        entrypoint, p.join(packageRoot, 'out.dill'), vmPlatformDill);
    var result = await client.compile();
    client.accept();
    expect(result.compilerOutputLines, isEmpty);
    expect(result.errorCount, 0);
    expect(
        result.newSources,
        containsAll([
          File(entrypoint).uri,
          packageConfig.resolve(Uri.parse('package:path/path.dart')),
        ]));
    expect(result.removedSources, isEmpty);
    expect(result.wasIncremental, isFalse);
    expect(File(result.dillOutput).existsSync(), true);
    var process = await Process.start(Platform.resolvedExecutable, [
      '--observe',
      '--no-pause-isolates-on-exit',
      '--pause-isolates-on-start',
      result.dillOutput
    ]);
    addTearDown(process.kill);
    var stdoutLines = StreamQueue(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));

    var observatoryLine = await stdoutLines.next;
    var observatoryUri =
        '${observatoryLine.split(' ').last.replaceFirst('http', 'ws')}ws';
    var vmService = await vmServiceConnectUri(observatoryUri);
    var vm = await vmService.getVM();
    await vmService.resume(vm.isolates.first.id);

    expect(await stdoutLines.next, p.join('hello', 'world'));

    var appFile = File(entrypoint);
    var originalContent = await appFile.readAsString();
    var newContent = originalContent.replaceFirst('hello', 'goodbye');
    await appFile.writeAsString(newContent);

    result = await client.compile([File(entrypoint).uri]);
    client.accept();
    expect(result.newSources, isEmpty);
    expect(result.removedSources, isEmpty);
    expect(result.compilerOutputLines, isEmpty);
    expect(result.errorCount, 0);
    expect(result.dillOutput, endsWith('.incremental.dill'));
    expect(result.wasIncremental, true);

    await vmService.reloadSources(vm.isolates.first.id,
        rootLibUri: result.dillOutput);

    expect(await stdoutLines.next, p.join('goodbye', 'world'));
    expect(await process.exitCode, 0);
  });

  test('can handle compile errors and reload fixes', () async {
    var entrypoint = p.join(packageRoot, 'bin', 'main.dart');
    var entrypointFile = File(entrypoint);
    var originalContent = await entrypointFile.readAsString();
    // append two compile errors to the bottom
    await entrypointFile
        .writeAsString('$originalContent\nint foo = 1.0;\nString bar = 4;');

    client = await FrontendServerClient.start(
        entrypoint, p.join(packageRoot, 'out.dill'), vmPlatformDill);
    var result = await client.compile();
    client.accept();
    expect(result.errorCount, 2);
    expect(result.compilerOutputLines,
        allOf(contains('int foo = 1.0;'), contains('String bar = 4;')));
    expect(
        result.newSources,
        containsAll([
          File(entrypoint).uri,
          packageConfig.resolve(Uri.parse('package:path/path.dart')),
        ]));
    expect(result.removedSources, isEmpty);
    expect(result.wasIncremental, isFalse);
    expect(File(result.dillOutput).existsSync(), true);

    var process = await Process.start(Platform.resolvedExecutable, [
      '--observe',
      '--no-pause-isolates-on-exit',
      '--pause-isolates-on-start',
      result.dillOutput
    ]);
    addTearDown(process.kill);
    var stdoutLines = StreamQueue(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));

    var observatoryLine = await stdoutLines.next;
    var observatoryUri =
        '${observatoryLine.split(' ').last.replaceFirst('http', 'ws')}ws';
    var vmService = await vmServiceConnectUri(observatoryUri);
    var vm = await vmService.getVM();
    await vmService.resume(vm.isolates.first.id);
    // The program actually runs regardless of the errors, as they dont affect
    // the runtime behavior.
    expect(await stdoutLines.next, p.join('hello', 'world'));

    await entrypointFile
        .writeAsString(originalContent.replaceFirst('hello', 'goodbye'));
    result = await client.compile([entrypointFile.uri]);
    client.accept();
    expect(result.errorCount, 0);
    expect(result.compilerOutputLines, isEmpty);
    expect(result.newSources, isEmpty);
    expect(result.removedSources, isEmpty);
    expect(result.wasIncremental, true);
    expect(File(result.dillOutput).existsSync(), true);

    await vmService.reloadSources(vm.isolates.first.id,
        rootLibUri: result.dillOutput);

    expect(await stdoutLines.next, p.join('goodbye', 'world'));
    expect(await process.exitCode, 0);
  });

  test('can compile and recompile a dartdevc app', () async {
    var entrypoint = p.join(packageRoot, 'bin', 'main.dart');
    var dartDevcClient = client = await DartDevcFrontendServerClient.start(
        entrypoint, p.join(packageRoot, 'out.dill'));
    var result = await client.compile();
    client.accept();
    expect(result.compilerOutputLines, isEmpty);
    expect(result.errorCount, 0);
    expect(
        result.newSources,
        containsAll([
          File(entrypoint).uri,
          packageConfig.resolve(Uri.parse('package:path/path.dart')),
        ]));
    expect(result.removedSources, isEmpty);
    expect(result.wasIncremental, isFalse);

    expect(File(result.jsManifestOutput).existsSync(), true);
    expect(File(result.jsSourcesOutput).existsSync(), true);
    expect(File(result.jsSourceMapsOutput).existsSync(), true);

    expect(utf8.decode(dartDevcClient.assetBytes('$entrypoint.lib.js')),
        contains('hello'));

    var appFile = File(entrypoint);
    var originalContent = await appFile.readAsString();
    var newContent = originalContent.replaceFirst('hello', 'goodbye');
    await appFile.writeAsString(newContent);

    result = await client.compile([File(entrypoint).uri]);
    client.accept();
    expect(result.newSources, isEmpty);
    expect(result.removedSources, isEmpty);
    expect(result.compilerOutputLines, isEmpty);
    expect(result.errorCount, 0);
    expect(result.jsManifestOutput, endsWith('.incremental.dill.json'));
    expect(result.wasIncremental, true);

    expect(utf8.decode(dartDevcClient.assetBytes('$entrypoint.lib.js')),
        contains('goodbye'));
  });
}

final vmPlatformDill =
    p.join(sdkDir, 'lib', '_internal', 'vm_platform_strong.dill');
final sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
final pubExecutable = p.join(p.dirname(Platform.resolvedExecutable),
    'pub${Platform.isWindows ? '.bat' : ''}');
