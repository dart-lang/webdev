// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

final _webdevBin = p.absolute(p.join('bin', 'webdev.dart'));

const webdevDirName = 'webdev';
const dwdsDirName = 'dwds';
const fixturesDirName = 'fixtures';

/// The path to the webdev directory in the local machine, e.g.
/// '/workstation/webdev'.
String get webdevPath {
  final pathParts = p.split(p.current);
  // We expect all tests to be run from the webdev mono-repo:
  assert(pathParts.contains(webdevDirName));
  return p.joinAll(
    pathParts.sublist(0, pathParts.indexOf(webdevDirName) + 1),
  );
}

/// The path to the fixtures directory in the local machine, e.g.
/// '/workstation/webdev/fixtures'.
String get fixturesPath {
  return p.join(webdevPath, fixturesDirName);
}

/// Expects one of [pathFromWebdev] or [pathFromFixtures] to be provided.
/// Returns the absolute path in the local machine to that path, e.g.
///   absolutePath(pathFromFixtures: '_test/example') ->
///   '/workstation/webdev/fixtures/_test/example'
String absolutePath({
  String? pathFromWebdev,
  String? pathFromFixtures,
}) {
  if (pathFromWebdev != null) {
    assert(pathFromFixtures == null);
    return p.normalize(p.join(webdevPath, pathFromWebdev));
  }
  if (pathFromFixtures != null) {
    assert(pathFromWebdev == null);
    return p.normalize(p.join(fixturesPath, pathFromFixtures));
  }
  throw Exception('Expected a path parameter.');
}

Future<TestProcess> runWebDev(List<String> args,
    {String? workingDirectory}) async {
  var fullArgs = [_webdevBin, ...args];

  return TestProcess.start(dartPath, fullArgs,
      workingDirectory: workingDirectory);
}

Future checkProcessStdout(TestProcess process, List items) async {
  for (var item in items) {
    if (item is! Matcher) {
      item = contains(item);
    }

    await expectLater(process.stdout, emitsThrough(item));
  }
}

/// Returns an environment map that includes `PUB_ENVIRONMENT`.
///
/// Maintains any existing values for this environment var.
/// Adds a new value that flags this is a bot/test and not human usage.
Map<String, String> getPubEnvironment() {
  var pubEnvironmentKey = 'PUB_ENVIRONMENT';
  var pubEnvironment = Platform.environment[pubEnvironmentKey] ?? '';
  if (pubEnvironment.isNotEmpty) {
    pubEnvironment = '$pubEnvironment;';
  }
  pubEnvironment = '${pubEnvironment}bot.pkg.webdev.test';

  var environment = {'PUB_ENVIRONMENT': pubEnvironment};

  return environment;
}
