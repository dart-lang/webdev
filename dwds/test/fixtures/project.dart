// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'utilities.dart';

enum NullSafety { weak, sound }

enum IndexBaseMode { noBase, base }

/// Project definitions from projects defined in webdev/fixtures.
class TestProject {
  final String packageName;
  final String packageDirectory;
  final String webAssetsPath;
  final String dartEntryFileName;
  final String htmlEntryFileName;
  final NullSafety nullSafety;

  String get absolutePackageDirectory =>
      absolutePath(pathFromFixtures: packageDirectory);

  // _test_package

  const TestProject.testPackageWithSoundNullSafety(
      {IndexBaseMode baseMode = IndexBaseMode.noBase})
      : this._(
          packageName: '_test_package_sound',
          packageDirectory: '_testPackageSound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName:
              baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
          nullSafety: NullSafety.sound,
        );

  const TestProject.testPackageWithWeakNullSafety(
      {IndexBaseMode baseMode = IndexBaseMode.noBase})
      : this._(
          packageName: '_test_package',
          packageDirectory: '_testPackage',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName:
              baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
          nullSafety: NullSafety.weak,
        );

  factory TestProject.testPackage({
    NullSafety nullSafety = NullSafety.sound,
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) =>
      nullSafety == NullSafety.sound
          ? TestProject.testPackageWithSoundNullSafety(baseMode: baseMode)
          : TestProject.testPackageWithWeakNullSafety(baseMode: baseMode);

  /// _test_circular1

  static const testCircular1WithSoundNullSafety = TestProject._(
    packageName: '_test_circular1_sound',
    packageDirectory: '_testCircular1Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.sound,
  );

  static const testCircular1WithWeakNullSafety = TestProject._(
    packageName: '_test_circular1',
    packageDirectory: '_testCircular1',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.weak,
  );

  factory TestProject.testCircular1(
          {NullSafety nullSafety = NullSafety.sound}) =>
      nullSafety == NullSafety.sound
          ? TestProject.testCircular1WithSoundNullSafety
          : TestProject.testCircular1WithWeakNullSafety;

  /// _test_circular2

  const TestProject.testCircular2WithSoundNullSafety(
      {IndexBaseMode baseMode = IndexBaseMode.noBase})
      : this._(
          packageName: '_test_circular2_sound',
          packageDirectory: '_testCircular2Sound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName:
              baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
          nullSafety: NullSafety.sound,
        );

  const TestProject.testCircular2WithWeakNullSafety(
      {IndexBaseMode baseMode = IndexBaseMode.noBase})
      : this._(
          packageName: '_test_circular2',
          packageDirectory: '_testCircular2',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName:
              baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
          nullSafety: NullSafety.weak,
        );

  factory TestProject.testCircular2({
    NullSafety nullSafety = NullSafety.sound,
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) =>
      nullSafety == NullSafety.sound
          ? TestProject.testCircular2WithSoundNullSafety(baseMode: baseMode)
          : TestProject.testCircular2WithWeakNullSafety(baseMode: baseMode);

  /// _test

  static const testWithSoundNullSafety = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: 'example/hello_world',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.sound,
  );

  static const testWithWeakNullSafety = TestProject._(
    packageName: '_test',
    packageDirectory: '_test',
    webAssetsPath: 'example/hello_world',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.weak,
  );

  factory TestProject.test({NullSafety nullSafety = NullSafety.sound}) =>
      nullSafety == NullSafety.sound
          ? TestProject.testWithSoundNullSafety
          : TestProject.testWithWeakNullSafety;

  static final testScopesWithSoundNullSafety = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: webCompatiblePath(['example', 'scopes']),
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'scopes.html',
    nullSafety: NullSafety.sound,
  );

  static final testAppendBodyWithSoundNullSafety = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: webCompatiblePath(['example', 'append_body']),
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.sound,
  );

  static const testExperimentWithSoundNullSafety = TestProject._(
    packageName: '_experiment_sound',
    packageDirectory: '_experimentSound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.sound,
  );

  const TestProject._({
    required this.packageName,
    required this.packageDirectory,
    required this.webAssetsPath,
    required this.dartEntryFileName,
    required this.htmlEntryFileName,
    required this.nullSafety,
  });

  void validate() {
    // Verify that the test fixtures package matches the null-safety mode:
    final isSoundPackage = packageDirectory.toLowerCase().contains('sound');
    assert(nullSafety == NullSafety.sound ? isSoundPackage : !isSoundPackage);

    // Verify that the web assets path has no starting slash:
    assert(!webAssetsPath.startsWith('/'));
  }
}
