// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const webdevDirName = 'webdev';
const dwdsDirName = 'dwds';
const fixturesDirName = 'fixtures';

/// The path to the project root directory, e.g. `webdev/` or `pkg/` in the
/// Dart SDK.
String get projectRootDir {
  return p.dirname(_testCommonPackageRoot);
}

/// The path to the DWDS directory in the local machine, e.g.
/// '/workstation/webdev/dwds'.
String get dwdsPath {
  return p.join(projectRootDir, dwdsDirName);
}

String get _testCommonPackageRoot {
  final scriptPath = Platform.script.toFilePath();
  final isTest = scriptPath.contains('dart_test.kernel');
  if (isTest) {
    return p.current; // p.current is the package root for tests
  }
  var current = p.dirname(scriptPath);
  while (current != p.dirname(current)) {
    if (File(p.join(current, 'pubspec.yaml')).existsSync()) {
      return current; // This is the package root
    }
    current = p.dirname(current);
  }
  throw StateError(
    'Could not find test_common package root from ${Platform.script.path}.',
  );
}

/// The path to the fixtures directory in the local machine, e.g.
/// '/workstation/webdev/fixtures'.
String get fixturesPath {
  return p.join(_testCommonPackageRoot, fixturesDirName);
}

// Creates a path compatible for web.
String webCompatiblePath(List<String> pathParts) {
  // Note: Replacing "\" with "/" is necessary because `joinAll` uses "\" if
  // the platform is Windows. However, only "/" is expected by the browser.
  return p.joinAll([...pathParts]).replaceAll('\\', '/');
}

/// Expects one of [pathFromProjectRoot], [pathFromDwds] or [pathFromFixtures] to be
/// provided. Returns the absolute path in the local machine to that path, e.g.
///   absolutePath(pathFromFixtures: '_test/example') ->
///   '/workstation/webdev/fixtures/_test/example'
String absolutePath({
  String? pathFromProjectRoot,
  String? pathFromDwds,
  String? pathFromFixtures,
}) {
  if (pathFromProjectRoot != null) {
    assert(pathFromDwds == null && pathFromFixtures == null);
    return p.normalize(p.join(projectRootDir, pathFromProjectRoot));
  }
  if (pathFromDwds != null) {
    assert(pathFromFixtures == null);
    return p.normalize(p.join(dwdsPath, pathFromDwds));
  }
  if (pathFromFixtures != null) {
    assert(pathFromDwds == null && pathFromProjectRoot == null);
    return p.normalize(p.join(fixturesPath, pathFromFixtures));
  }
  throw Exception('Expected a path parameter.');
}

bool dartSdkIsAtLeast(String sdkVersion) {
  final expectedVersion = Version.parse(sdkVersion);
  final actualVersion = Version.parse(Platform.version.split(' ')[0]);
  return actualVersion >= expectedVersion;
}
