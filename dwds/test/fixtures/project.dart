// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test_common/utilities.dart';

enum IndexBaseMode { noBase, base }

/// Project definitions from projects defined in webdev/fixtures.
class TestProject {
  final String packageName;
  final String packageDirectory;
  final String webAssetsPath;
  final String dartEntryFileName;
  final String htmlEntryFileName;

  /// The top level directory in which we run the test server, e.g.
  /// "/workstation/webdev/fixtures/_testSound".
  String get absolutePackageDirectory =>
      absolutePath(pathFromFixtures: packageDirectory);

  /// The directory to build and serve, e.g. "example".
  String get directoryToServe => p.split(webAssetsPath).first;

  /// The path to the HTML file to serve, relative to the [directoryToServe],
  /// e.g. "hello_world/index.html".
  String get filePathToServe {
    final pathParts = p
        .split(webAssetsPath)
        .where((pathPart) => pathPart != directoryToServe);
    return webCompatiblePath([...pathParts, htmlEntryFileName]);
  }

  /// The path to the Dart entry file, e.g,
  /// "/workstation/webdev/fixtures/_testSound/example/hello_world/main.dart":
  String get dartEntryFilePath => absolutePath(
    pathFromFixtures: p.joinAll([
      packageDirectory,
      webAssetsPath,
      dartEntryFileName,
    ]),
  );

  /// The URI for the package_config.json is located in:
  /// `<project directory>/.dart_tool/package_config`
  Uri get packageConfigFile => p.toUri(
    p.join(absolutePackageDirectory, '.dart_tool', 'package_config.json'),
  );

  /// The package URI of the Dart entry file, e.g,
  /// "org-dartlang-app:example/hello_world/main.dart":
  Uri get dartEntryFilePackageUri => Uri.parse(
    'org-dartlang-app:///${p.join(webAssetsPath, dartEntryFileName)}',
  );

  const TestProject.testPackage({IndexBaseMode baseMode = IndexBaseMode.noBase})
    : this._(
        packageName: '_test_package_sound',
        packageDirectory: '_testPackageSound',
        webAssetsPath: 'web',
        dartEntryFileName: 'main.dart',
        htmlEntryFileName:
            baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
      );

  static const testCircular1 = TestProject._(
    packageName: '_test_circular1_sound',
    packageDirectory: '_testCircular1Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  const TestProject.testCircular2({
    IndexBaseMode baseMode = IndexBaseMode.noBase,
  }) : this._(
         packageName: '_test_circular2_sound',
         packageDirectory: '_testCircular2Sound',
         webAssetsPath: 'web',
         dartEntryFileName: 'main.dart',
         htmlEntryFileName:
             baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
       );

  static const test = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: 'example/hello_world',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  static final testScopes = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: webCompatiblePath(['example', 'scopes']),
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'scopes.html',
  );

  static final testAppendBody = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: webCompatiblePath(['example', 'append_body']),
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  static const testExperiment = TestProject._(
    packageName: '_experiment_sound',
    packageDirectory: '_experimentSound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  static const testHotRestart1 = TestProject._(
    packageName: '_test_hot_restart1',
    packageDirectory: '_testHotRestart1Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  /// This series of hot restart tests is divided across multiple packages in
  /// order to test correctness when only a subset of libraries are updated.
  static const testHotRestart2 = TestProject._(
    packageName: '_test_hot_restart2',
    packageDirectory: '_testHotRestart2Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  const TestProject._({
    required this.packageName,
    required this.packageDirectory,
    required this.webAssetsPath,
    required this.dartEntryFileName,
    required this.htmlEntryFileName,
  });

  void validate() {
    // Verify that the web assets path has no starting slash:
    assert(!webAssetsPath.startsWith('/'));
  }

  /// Clean up the project.
  /// Called when we need to rebuild sdk and the app from
  /// previous test configurations.
  Future<void> cleanUp() async {
    await Process.run('dart', [
      'run',
      'build_runner',
      'clean',
    ], workingDirectory: absolutePackageDirectory,);
  }

  /// The path to the Dart specified file in the 'lib' directory, e.g,
  /// "/workstation/webdev/fixtures/_testSound/lib/library.dart":
  String dartLibFilePath(String dartLibFileName) => absolutePath(
    pathFromFixtures: p.joinAll([packageDirectory, 'lib', dartLibFileName]),
  );
}
