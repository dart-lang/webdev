// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const webdevDirName = 'webdev';
const dwdsDirName = 'dwds';
const fixturesDirName = 'fixtures';

/// The path to the project root directory, e.g. `webdev/` or `pkg/` in the
/// Dart SDK.
String get projectRootDir {
  return p.dirname(_dwdsTestCommonPackageRoot);
}

/// The path to the DWDS directory in the local machine, e.g.
/// 'webdev/dwds' or 'pkg/dwds'.
String get dwdsPath {
  return p.join(projectRootDir, dwdsDirName);
}

/// The path to the fixtures directory in the local machine, e.g.
/// 'webdev/dwds_test_common/fixtures' or 'pkg/dwds_test_common/fixtures'.
String get fixturesPath {
  return p.join(_dwdsTestCommonPackageRoot, fixturesDirName);
}

/// The path to the webdev/dwds_test_common or pkg/dwds_test_common package
/// root in the local machine, e.g. 'webdev/dwds_test_common' or
/// 'pkg/dwds_test_common'.
String get _dwdsTestCommonPackageRoot {
  // Try to resolve any `package:dwds_test_common` file.
  final packageUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:dwds_test_common/utilities.dart'),
  );
  if (packageUri != null) {
    // Strip `lib/utilities.dart`.
    return p.dirname(p.dirname(packageUri.toFilePath()));
  }
  // If there's no package config, try to find it from the current dir.
  for (var dir = p.current; dir != p.dirname(dir); dir = p.dirname(dir)) {
    final file = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (!file.existsSync()) continue;
    final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    for (final package in config['packages'] as List<Object?>) {
      if (package case {
        'name': 'dwds_test_common',
        'rootUri': final String rootUri,
      }) {
        return p.fromUri(file.uri.resolve(rootUri));
      }
    }
  }
  throw StateError('Could not find dwds_test_common from ${p.current}.');
}

// Creates a path compatible for web.
String webCompatiblePath(List<String> pathParts) {
  final context = p.Context(style: p.Style.posix);
  return context.joinAll([...pathParts]);
}

/// Expects one of [pathFromWebdev], [pathFromDwds] or [pathFromFixtures] to
/// be provided. Returns the absolute path in the local machine to that path,
/// e.g. absolutePath(pathFromFixtures: '_test/example') ->
/// '/workstation/webdev/dwds_test_common/fixtures/_test/example'
String absolutePath({
  String? pathFromWebdev,
  String? pathFromDwds,
  String? pathFromFixtures,
}) {
  if (pathFromWebdev != null) {
    assert(pathFromDwds == null && pathFromFixtures == null);
    return p.normalize(p.join(projectRootDir, pathFromWebdev));
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
