// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'utilities.dart';

enum NullSafety { weak, sound }

enum IndexBaseMode { noBase, base }

/// Project definitions from projects defined in webdev/fixtures.
class TestProject {
  final String packageDirectory;
  final String webAssetsPath;
  final String dartEntryFileName;
  final String htmlEntryFileName;
  final NullSafety nullSafety;

  static String _index(IndexBaseMode baseMode) =>
      baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html';

  TestProject.testPackage({
    NullSafety nullSafety = NullSafety.sound,
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
          packageDirectory: nullSafety == NullSafety.sound
              ? '_testPackageSound'
              : '_testPackage',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: _index(baseMode),
          nullSafety: nullSafety,
        );

  TestProject.testPackageWithSoundNullSafety() : this.testPackage();

  TestProject.testCircular({
    NullSafety nullSafety = NullSafety.sound,
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
          packageDirectory: nullSafety == NullSafety.sound
              ? '_testCircular2Sound'
              : '_testCircular2',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: _index(baseMode),
          nullSafety: nullSafety,
        );

  TestProject.testWithSoundNullSafety()
      : this._(
          packageDirectory: '_testSound',
          webAssetsPath: 'example/hello_world',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: 'index.html',
          nullSafety: NullSafety.sound,
        );

  TestProject.testScopesWithSoundNullSafety()
      : this._(
          packageDirectory: '_testSound',
          webAssetsPath: webCompatiblePath(['example', 'scopes']),
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: 'scopes.html',
          nullSafety: NullSafety.sound,
        );

  TestProject.testAppendBodyWithSoundNullSafety()
      : this._(
          packageDirectory: '_testSound',
          webAssetsPath: webCompatiblePath(['example', 'append_body']),
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: 'index.html',
          nullSafety: NullSafety.sound,
        );

  TestProject.testExperimentWithSoundNullSafety()
      : this._(
          packageDirectory: '_experimentSound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: 'index.html',
          nullSafety: NullSafety.sound,
        );

  TestProject._({
    required this.packageDirectory,
    required this.webAssetsPath,
    required this.dartEntryFileName,
    required this.htmlEntryFileName,
    required this.nullSafety,
  }) {
    // Verify that the test fixtures package matches the null-safety mode:
    final isSoundPackage = packageDirectory.toLowerCase().contains('sound');
    assert(nullSafety == NullSafety.sound ? isSoundPackage : !isSoundPackage);

    // Verify that the web assets path has no starting slash:
    assert(!webAssetsPath.startsWith('/'));
  }
}
