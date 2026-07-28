// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:dwds/src/loaders/asset_scheme.dart';

/// Translates paths across DDC, Frontend Server, DWDS, and package:build.
class WebPathTranslator {
  static String _modifyLibSegment(String serverPath, {required bool add}) {
    serverPath = serverPath.replaceAll('\\', '/');
    if (!serverPath.startsWith('packages/')) return serverPath;
    final segments = serverPath.split('/');
    if (segments.length > 2) {
      final isLib = segments[2] == 'lib';
      if (add && !isLib) {
        return 'packages/${segments[1]}/lib/${segments.skip(2).join('/')}';
      }
      if (!add && isLib) {
        return 'packages/${segments[1]}/${segments.skip(3).join('/')}';
      }
    }
    return serverPath;
  }

  /// Adds 'lib' to a package path.
  ///
  /// Example: packages/foo/bar.dart -> packages/foo/lib/bar.dart
  static String addLibSegment(String serverPath) =>
      _modifyLibSegment(serverPath, add: true);

  /// Removes 'lib' from a package path.
  ///
  /// Example: packages/foo/lib/bar.dart -> packages/foo/bar.dart
  static String removeLibSegment(String serverPath) =>
      _modifyLibSegment(serverPath, add: false);

  /// Translates a 'lib/' path to a package path.
  ///
  /// DDC generates source maps with relative paths from the generated output.
  /// Files in the root package can resolve to 'lib/' references, so we prepend
  /// `packages/[rootPackageName]/` to resolve them to a package path. Example:
  /// `lib/foo.dart` -> `packages/root_package/foo.dart`
  static String translateLibPathToPackagePath(
    String uri,
    String? rootPackageName,
  ) {
    if (uri.startsWith('lib/')) {
      if (rootPackageName == null || rootPackageName.isEmpty) {
        throw StateError(
          'Cannot translate lib/ path without a root package name. URI: $uri',
        );
      }
      return 'packages/$rootPackageName/${uri.substring('lib/'.length)}';
    }
    return uri;
  }

  /// Maps module extensions between layouts.
  ///
  /// For example, from [FrontendServerAssetScheme] to
  /// [BuildRunnerAssetScheme]:
  ///   `main.dart.lib` -> `main.ddc`
  ///   `main.dart.lib.js` -> `main.ddc.js`
  static String translateModuleExtension(
    String path, {
    required AssetScheme from,
    required AssetScheme to,
  }) {
    if (from.descriptorSuffix == to.descriptorSuffix) return path;
    return path.replaceAll(from.descriptorSuffix, to.descriptorSuffix);
  }

  /// Maps '.dart.lib' (FES suffix) to '.ddc' (package:build suffix).
  static String translateFesToBuildRunnerPath(String path) {
    return translateModuleExtension(
      path,
      from: FrontendServerAssetScheme(),
      to: BuildRunnerAssetScheme(),
    );
  }

  static const defaultWebDirs = ['web', 'test', 'example', 'benchmark'];

  /// Reconstructs the `org-dartlang-app:///` scheme for paths.
  ///
  /// This is required for relative sourcemaps emitted by the Frontend Server,
  /// which lack a scheme (such as `/web/main.dart`).
  static String reconstructAppScheme(String path, String scriptLocation) {
    if (path.startsWith('org-dartlang-app:')) return path;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final isWebDir = defaultWebDirs.any(
      (dir) => normalizedPath.startsWith('/$dir/'),
    );
    if (isWebDir) {
      // Example:
      //   scriptLocation: `/`
      //   path:  `/web/main.dart`
      //   after: `org-dartlang-app:///web/main.dart`
      return 'org-dartlang-app://$normalizedPath';
    }
    if (scriptLocation.startsWith('/packages/') &&
        !normalizedPath.startsWith('/packages/')) {
      // Example:
      //   scriptLocation: `/packages/my_package/subdir/main.ddc.js`
      //   path:  `/lib/src/library.dart`
      //   after: `org-dartlang-app:///packages/my_package/src/library.dart`
      final packageDir = scriptLocation.split('/').take(3).join('/');
      final relativePath = normalizedPath.startsWith('/lib/')
          ? normalizedPath.substring('/lib/'.length)
          : normalizedPath.substring(1);
      return 'org-dartlang-app://$packageDir/$relativePath';
    }
    return path;
  }
}
