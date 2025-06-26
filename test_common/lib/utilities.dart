// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const webdevDirName = 'webdev';
const dwdsDirName = 'dwds';
const fixturesDirName = 'fixtures';

const newDdcTypeSystemVersion = '3.3.0-242.0.dev';

/// The path to the webdev directory in the local machine, e.g.
/// '/workstation/webdev'.
String get webdevPath {
  final pathParts = p.split(p.current);
  // We expect all tests to be run from the webdev mono-repo:
  assert(pathParts.contains(webdevDirName));
  return p.joinAll(
    pathParts.sublist(0, pathParts.lastIndexOf(webdevDirName) + 1),
  );
}

/// The path to the DWDS directory in the local machine, e.g.
/// '/workstation/webdev/dwds'.
String get dwdsPath {
  return p.join(webdevPath, dwdsDirName);
}

/// The path to the fixtures directory in the local machine, e.g.
/// '/workstation/webdev/fixtures'.
String get fixturesPath {
  return p.join(webdevPath, fixturesDirName);
}

// Creates a path compatible for web.
String webCompatiblePath(List<String> pathParts) {
  // Note: Replacing "\" with "/" is necessary because `joinAll` uses "\" if
  // the platform is Windows. However, only "/" is expected by the browser.
  return p.joinAll([...pathParts]).replaceAll('\\', '/');
}

/// Expects one of [pathFromWebdev], [pathFromDwds] or [pathFromFixtures]  to be
/// provided. Returns the absolute path in the local machine to that path, e.g.
///   absolutePath(pathFromFixtures: '_test/example') ->
///   '/workstation/webdev/fixtures/_test/example'
String absolutePath({
  String? pathFromWebdev,
  String? pathFromDwds,
  String? pathFromFixtures,
}) {
  if (pathFromWebdev != null) {
    assert(pathFromDwds == null && pathFromFixtures == null);
    return p.normalize(p.join(webdevPath, pathFromWebdev));
  }
  if (pathFromDwds != null) {
    assert(pathFromFixtures == null);
    return p.normalize(p.join(dwdsPath, pathFromDwds));
  }
  if (pathFromFixtures != null) {
    assert(pathFromDwds == null && pathFromWebdev == null);
    return p.normalize(p.join(fixturesPath, pathFromFixtures));
  }
  throw Exception('Expected a path parameter.');
}

bool dartSdkIsAtLeast(String sdkVersion) {
  final expectedVersion = Version.parse(sdkVersion);
  final actualVersion = Version.parse(Platform.version.split(' ')[0]);
  return actualVersion >= expectedVersion;
}
