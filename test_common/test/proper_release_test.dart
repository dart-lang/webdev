// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:test_common/utilities.dart';

void main() {
  for (var package in ['dwds', 'webdev']) {
    test('$package is following proper release procedure', () async {
      final pubspecPath =
          absolutePath(pathFromWebdev: p.join(package, 'pubspec.yaml'));
      final pubspec = Pubspec.parse(File(pubspecPath).readAsStringSync());
      final version = pubspec.version!;
      final isDev = version.toString().contains('dev');
      if (!isDev) {
        final wasReleased =
            await _versionWasReleased(package, version: version);
        expect(wasReleased, isTrue,
            reason: _versionNotReleasedReason(package, version: version));
      }
      expect(isDev, isTrue,
          reason: _noDevVersionReason(package, version: version));
    });
  }
}

String _releaseTagName(String package, {required Version version}) =>
    '$package-v$version';

Future<bool> _versionWasReleased(String package,
    {required Version version}) async {
  final releaseTagName = _releaseTagName(package, version: version);
  final gitProcess = await Process.run(
    'git',
    ['tag', '-l', '|', 'grep', releaseTagName],
  );
  final stdout = gitProcess.stdout as String;
  return stdout.contains(releaseTagName);
}

String _versionNotReleasedReason(String package, {required Version version}) {
  final releaseTagName = _releaseTagName(package, version: version);
  return '''
    NOTE: If this PR is to prepare a release, please add the "prepare-release" 
    label to skip this test.

    The current $package version has not been released. Please create a new
    release with name $releaseTagName. 
    ''';
}

String _noDevVersionReason(String package, {required Version? version}) {
  final nextPatch = version?.nextPatch;
  final nextDevVersion = nextPatch != null ? '$nextPatch-dev' : '[dev version]';
  return '''
    NOTE: If this PR is to prepare a release, please add the "prepare-release" 
    label to skip this test.

    $package uses a dev version for development. Current version is $version.
    If $package was just published, please open a new PR to reset it with:
    dart run release.dart --reset -p $package -v $nextDevVersion
    ''';
}
