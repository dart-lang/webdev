// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  watch.start();
  if (args.isNotEmpty) {
    throw ArgumentError('No command line args are supported');
  }

  var client = await DartDevcFrontendServerClient.start(
      'org-dartlang-root:///$app', outputDill,
      fileSystemRoots: [p.current], fileSystemScheme: 'org-dartlang-root');
  _print('compiling $app');
  await client.compile([]);
  client.accept();
  _print('done compiling $app');

  _print('editing $app');
  var appFile = File(app);
  var originalContent = await appFile.readAsString();
  var newContent = originalContent.replaceFirst('hello', 'goodbye');
  await appFile.writeAsString(newContent);

  _print('recompiling $app with edits');
  await client.compile([Uri.parse('org-dartlang-root:///$app')]);
  client.accept();
  _print('done recompiling $app');

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
final sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
final watch = Stopwatch();
