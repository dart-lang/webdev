// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test_common/utilities.dart';

enum IndexBaseMode { noBase, base }

/// Project definitions from projects defined in webdev/fixtures.
class TestProject {
  final String packageName;
  final String packageDirectory;
  final String webAssetsPath;
  final String dartEntryFileName;
  final String htmlEntryFileName;
  final bool editable;

  late Directory _fixturesCopy;

  /// The top level directory in which we run the test server, e.g.
  /// "/workstation/webdev/fixtures/_testSound".
  String get absolutePackageDirectory =>
      editable
          ? p.join(_fixturesCopy.absolute.path, packageDirectory)
          : absolutePath(pathFromFixtures: packageDirectory);

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
  String get dartEntryFilePath {
    final entryFilePathInPkg = [
      packageDirectory,
      webAssetsPath,
      dartEntryFileName,
    ];
    return editable
        ? p.joinAll([_fixturesCopy.absolute.path, ...entryFilePathInPkg])
        : absolutePath(pathFromFixtures: p.joinAll(entryFilePathInPkg));
  }

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

  TestProject.testPackage({IndexBaseMode baseMode = IndexBaseMode.noBase})
    : this._(
        packageName: '_test_package_sound',
        packageDirectory: '_testPackageSound',
        webAssetsPath: 'web',
        dartEntryFileName: 'main.dart',
        htmlEntryFileName:
            baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
      );

  static final testCircular1 = TestProject._(
    packageName: '_test_circular1_sound',
    packageDirectory: '_testCircular1Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  TestProject.testCircular2({IndexBaseMode baseMode = IndexBaseMode.noBase})
    : this._(
        packageName: '_test_circular2_sound',
        packageDirectory: '_testCircular2Sound',
        webAssetsPath: 'web',
        dartEntryFileName: 'main.dart',
        htmlEntryFileName:
            baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html',
      );

  static final test = TestProject._(
    packageName: '_test_sound',
    packageDirectory: '_testSound',
    webAssetsPath: 'example/hello_world',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    editable: true,
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
    editable: true,
  );

  static final testExperiment = TestProject._(
    packageName: '_experiment_sound',
    packageDirectory: '_experimentSound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  static final testHotRestart1 = TestProject._(
    packageName: '_test_hot_restart1',
    packageDirectory: '_testHotRestart1Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
  );

  /// This series of hot restart tests is divided across multiple packages in
  /// order to test correctness when only a subset of libraries are updated.
  static final testHotRestart2 = TestProject._(
    packageName: '_test_hot_restart2',
    packageDirectory: '_testHotRestart2Sound',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    editable: true,
  );

  static final testHotRestartBreakpoints = TestProject._(
    packageName: '_test_hot_restart_breakpoints',
    packageDirectory: '_testHotRestartBreakpoints',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    editable: true,
  );

  static final testHotReload = TestProject._(
    packageName: '_test_hot_reload',
    packageDirectory: '_testHotReload',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    editable: true,
  );

  static final testHotReloadBreakpoints = TestProject._(
    packageName: '_test_hot_reload_breakpoints',
    packageDirectory: '_testHotReloadBreakpoints',
    webAssetsPath: 'web',
    dartEntryFileName: 'main.dart',
    htmlEntryFileName: 'index.html',
    editable: true,
  );

  TestProject._({
    required this.packageName,
    required this.packageDirectory,
    required this.webAssetsPath,
    required this.dartEntryFileName,
    required this.htmlEntryFileName,
    this.editable = false,
  });

  static void _copyPackageAndPathDependenciesIntoTempDirectory(
    Directory tempDirectory,
    String packageDirectory,
    Set<String> copiedPackageDirectories,
  ) {
    // There may be cycles in dependencies, so check that we already copied this
    // package.
    if (copiedPackageDirectories.contains(packageDirectory)) return;
    final currentPath = absolutePath(pathFromFixtures: packageDirectory);
    final newPath = p.join(tempDirectory.absolute.path, packageDirectory);
    Directory(newPath).createSync();
    copyPathSync(currentPath, newPath);
    copiedPackageDirectories.add(packageDirectory);
    final pubspec = Pubspec.parse(
      File(p.join(currentPath, 'pubspec.yaml')).readAsStringSync(),
    );
    for (final package in pubspec.dependencies.keys) {
      final dependency = pubspec.dependencies[package]!;
      if (dependency is PathDependency) {
        final dependencyDirectory = Directory(dependency.path);
        // It may be okay to do some more complicated copying here for path
        // dependencies that aren't immediately under `fixtures`, but for now,
        // only support those that are.
        assert(
          dependencyDirectory.parent == Directory(currentPath).parent,
          'Path dependency of $packageDirectory: '
          '${dependencyDirectory.absolute.path} is not an immediate directory '
          'in `fixtures`.',
        );
        _copyPackageAndPathDependenciesIntoTempDirectory(
          tempDirectory,
          p.dirname(dependencyDirectory.path),
          copiedPackageDirectories,
        );
      }
    }
  }

  Future<void> setUp() async {
    // Verify that the web assets path has no starting slash.
    assert(!webAssetsPath.startsWith('/'));
    // If this project is editable, we should use a copy of the package to edit
    // instead.
    if (editable) {
      final systemTempDir = Directory(
        // Resolve symbolic links as build_daemon tests rely on paths matching
        // between the client and the daemon.
        Directory.systemTemp.resolveSymbolicLinksSync(),
      );
      _fixturesCopy = systemTempDir.createTempSync();
      _copyPackageAndPathDependenciesIntoTempDirectory(
        _fixturesCopy,
        packageDirectory,
        {},
      );
    }

    // Clean up the project.
    // Called when we need to rebuild sdk and the app from previous test
    // configurations.
    await Process.run('dart', [
      'run',
      'build_runner',
      'clean',
    ], workingDirectory: absolutePackageDirectory);
  }

  /// Delete the project if we made a copy.
  void tearDown() {
    if (editable) {
      _fixturesCopy.deleteSync(recursive: true);
    }
  }

  /// The path to the Dart specified file in the 'lib' directory, e.g,
  /// "/workstation/webdev/fixtures/_testSound/lib/library.dart":
  String dartLibFilePath(String dartLibFileName) {
    final libFilePathInPkg = [packageDirectory, 'lib', dartLibFileName];
    return editable
        ? p.joinAll([_fixturesCopy.absolute.path, ...libFilePathInPkg])
        : absolutePath(pathFromFixtures: p.joinAll(libFilePathInPkg));
  }
}
