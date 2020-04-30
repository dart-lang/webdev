// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;

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

  if (target == 'vm') await _runApp();

  _print('editing $app');
  var appFile = File(app);
  var originalContent = await appFile.readAsString();
  var newContent = originalContent.replaceFirst('hello', 'goodbye');
  await appFile.writeAsString(newContent);

  _print('recompiling $app with edits');
  // TODO: Implement hot reload and/or patch the incremental dill.
  client.reset();
  await client.compile([Uri.parse('org-dartlang-root:///$app')]);
  client.accept();
  _print('done recompiling $app');
  if (target == 'vm') await _runApp();

  _print('restoring $app');
  await appFile.writeAsString(originalContent);
  _print('exiting');
  await client.shutdown();
}

Future<void> _runApp() async {
  _print('Running $app');
  var process = await Process.start(Platform.resolvedExecutable, [outputDill],
      mode: ProcessStartMode.inheritStdio);
  await process.exitCode;
}

void _print(String message) {
  print('${watch.elapsed}: $message');
}

final app = 'example/app/main.dart';
final outputDill = p.join('.dart_tool', 'out', 'example_app.dill');
final sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
final watch = Stopwatch();
