// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:test_common/utilities.dart';

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

  /// The top level directory in which we run the test server, e.g.
  /// "/workstation/webdev/fixtures/_testSound".
  String get absolutePackageDirectory =>
      absolutePath(pathFromFixtures: packageDirectory);

  /// The directory to build and serve, e.g. "example".
  String get directoryToServe => p.split(webAssetsPath).first;

  /// The path to the HTML file to serve, relative to the [directoryToServe],
  /// e.g. "hello_world/index.html".
  String get filePathToServe {
    final pathParts = p.split(webAssetsPath).where(
          (pathPart) => pathPart != directoryToServe,
        );
    return webCompatiblePath([...pathParts, htmlEntryFileName]);
  }

  /// The path to the Dart entry file, e.g,
  /// "/workstation/webdev/fixtures/_testSound/example/hello_world/main.dart":
  String get dartEntryFilePath => absolutePath(
        pathFromFixtures: p.joinAll(
          [
            packageDirectory,
            webAssetsPath,
            dartEntryFileName,
          ],
        ),
      );

  /// The URI for the package_config.json is located in:
  /// <project directory>/.dart_tool/package_config
  Uri get packageConfigFile => p.toUri(
        p.join(
          absolutePackageDirectory,
          '.dart_tool',
          'package_config.json',
        ),
      );

  /// The package URI of the Dart entry file, e.g,
  /// "org-dartlang-app:example/hello_world/main.dart":
  Uri get dartEntryFilePackageUri => Uri.parse('org-dartlang-app:///${p.join(
        webAssetsPath,
        dartEntryFileName,
      )}');

  const TestProject.testPackageWithSoundNullSafety({
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
          packageName: '_test_package_sound',
          packageDirectory: '_testPackageSound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName:
              baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
          nullSafety: NullSafety.sound,
        );

  const TestProject.testPackageWithWeakNullSafety({
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
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

  factory TestProject.testCircular1({
    NullSafety nullSafety = NullSafety.sound,
  }) =>
      nullSafety == NullSafety.sound
          ? TestProject.testCircular1WithSoundNullSafety
          : TestProject.testCircular1WithWeakNullSafety;

  const TestProject.testCircular2WithSoundNullSafety({
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
          packageName: '_test_circular2_sound',
          packageDirectory: '_testCircular2Sound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName:
              baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
          nullSafety: NullSafety.sound,
        );

  const TestProject.testCircular2WithWeakNullSafety({
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
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

  static const testHotRestart1 = TestProject._(
    packageName: '_test_hot_restart1',
    packageDirectory: '_testHotRestart1Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    nullSafety: NullSafety.sound,
  );

  /// This series of hot restart tests is divided across multiple packages in
  /// order to test correctness when only a subset of libraries are updated.
  static const testHotRestart2 = TestProject._(
    packageName: '_test_hot_restart2',
    packageDirectory: '_testHotRestart2Sound',
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

  /// Clean up the project.
  /// Called when we need to rebuild sdk and the app from
  /// previous test configurations.
  Future<void> cleanUp() async {
    await Process.run(
      'dart',
      ['run', 'build_runner', 'clean'],
      workingDirectory: absolutePackageDirectory,
    );
  }

  /// The path to the Dart specified file in the 'lib' directory, e.g,
  /// "/workstation/webdev/fixtures/_testSound/lib/library.dart":
  String dartLibFilePath(String dartLibFileName) => absolutePath(
        pathFromFixtures: p.joinAll(
          [
            packageDirectory,
            'lib',
            dartLibFileName,
          ],
        ),
      );
}
