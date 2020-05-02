// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

void main(List<String> args) async {
  watch.start();
  if (args.length > 1) {
    throw ArgumentError('Only one command line arg is allowed, the target type '
        '(either `vm` or `dartdevc`)');
  }
  var target = args.isEmpty ? 'vm' : args.first;
  if (target != 'vm' && target != 'dartdevc') {
    throw ArgumentError(
        'Only `vm` and `dartdevc` are supported as targets, but got '
        '`$target`');
  }

  var platformDill = target == 'vm'
      ? p.join(sdkDir, 'lib', '_internal', 'vm_platform_strong.dill')
      : p.join(sdkDir, 'lib', '_internal', 'ddc_sdk.dill');

  var client = await FrontendServerClient.start(
      'org-dartlang-root:///$app', outputDill, platformDill,
      target: target,
      fileSystemRoots: [p.current],
      fileSystemScheme: 'org-dartlang-root');
  _print('compiling $app');
  await client.compile([]);
  client.accept();
  _print('done compiling $app');

  Process appProcess;
  final vmServiceCompleter = Completer<VmService>();
  if (target == 'vm') {
    appProcess = await Process.start(Platform.resolvedExecutable,
        ['--observe', '--no-pause-isolates-on-exit', outputDill]);
    appProcess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stdout.writeln('APP -> $line');
      if (line.startsWith('Observatory listening on')) {
        var observatoryUri =
            '${line.split(' ').last.replaceFirst('http', 'ws')}ws';
        vmServiceCompleter.complete(vmServiceConnectUri(observatoryUri));
      }
    });
    appProcess.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderr.writeln('APP -> $line');
    });
  }

  final vmService = target == 'vm' ? await vmServiceCompleter.future : null;

  _print('editing $app');
  var appFile = File(app);
  var originalContent = await appFile.readAsString();
  var newContent = originalContent.replaceFirst('hello', 'goodbye');
  await appFile.writeAsString(newContent);

  _print('recompiling $app with edits');
  await client.compile([Uri.parse('org-dartlang-root:///$app')]);
  client.accept();
  _print('done recompiling $app');
  if (target == 'vm') {
    _print('reloading $app');
    var vm = await vmService.getVM();
    await vmService.reloadSources(vm.isolates.first.id,
        rootLibUri: outputIncrementalDill);
  }

  _print('restoring $app');
  await appFile.writeAsString(originalContent);
  _print('exiting');
  await client.shutdown();
}

void _print(String message) {
  print('${watch.elapsed}: $message');
}

final app = 'example/app/main.dart';
final outputDill = p.join('.dart_tool', 'out', 'example_app.dill');
final outputIncrementalDill =
    p.join('.dart_tool', 'out', 'example_app.dill.incremental.dill');
final sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
final watch = Stopwatch();
