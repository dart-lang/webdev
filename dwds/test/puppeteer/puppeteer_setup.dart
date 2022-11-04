// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../fixtures/context.dart';

const useSseFlagName = 'use-sse';

void main(List<String> arguments) async {
  exitCode = 0; // presume success

  // Parse command-line arguments:
  final parser = ArgParser()
    ..addFlag(
      useSseFlagName,
      negatable: true,
      defaultsTo: true,
      abbr: 's',
    );
  final argResults = parser.parse(arguments);
  final useSse = argResults[useSseFlagName] as bool;

  // Build the Dart Debug Extension:
  print('Building Dart Debug Extension...');
  final currentDir = Directory.current;
  final extensionDir = absoluteWebdevPath(
      currentPath: currentDir.path,
      relativeWebdevPath: 'dwds/debug_extension_mv3');
  await Process.run(
    'tool/build_extension.sh',
    [],
    workingDirectory: extensionDir,
  );

  // Create a test context to launch the test server:
  print('Starting a test server...');
  final context = TestContext(
    directory: absoluteWebdevPath(
      currentPath: currentDir.path,
      relativeWebdevPath: 'fixtures/_test',
    ),
    entry: absoluteWebdevPath(
      currentPath: currentDir.path,
      relativeWebdevPath: 'fixtures/_test/example/append_body/main.dart',
    ),
  );
  await context.setUp(serveDevTools: true, useSse: useSse, launchChrome: false);
  final appUrl = context.appUrl;

  // Install the node_modules:
  print('Installing node_modules...');
  await Process.run('npm', ['install']);
  final compiledExtensionDir = absoluteWebdevPath(
      currentPath: currentDir.path,
      relativeWebdevPath: 'dwds/debug_extension_mv3/compiled');

  print('============================================================');
  print('====================TEST RUNNER COMMAND:====================');
  print('============================================================');
  print('npm test extension.test.js -- $compiledExtensionDir $appUrl');
}

String absoluteWebdevPath(
    {required String currentPath, required String relativeWebdevPath}) {
  final currentPathParts = p.split(currentPath);
  final pathPartsToWebdev =
      currentPathParts.sublist(0, currentPathParts.indexOf('webdev') + 1);
  final relativePathParts = p.split(relativeWebdevPath);
  final pathToDir = p.joinAll([...pathPartsToWebdev, ...relativePathParts]);
  return pathToDir;
}
