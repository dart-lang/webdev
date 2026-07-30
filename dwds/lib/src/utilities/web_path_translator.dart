// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:dwds/src/loaders/asset_scheme.dart';
import 'package:dwds/src/loaders/strategy.dart';

/// Translates paths across DDC, Frontend Server, DWDS, and package:build.
class WebPathTranslator {
  static const _fesScheme = FrontendServerAssetScheme();
  static const _buildRunnerScheme = BuildRunnerAssetScheme();

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
  /// Example: `packages/foo/bar.dart` -> `packages/foo/lib/bar.dart`
  static String addLibSegment(String serverPath) =>
      _modifyLibSegment(serverPath, add: true);

  /// Removes 'lib' from a package path.
  ///
  /// Example: `packages/foo/lib/bar.dart` -> `packages/foo/bar.dart`
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

  /// Converts a `packages/` server path to a `package:` URI string.
  ///
  /// Examples:
  ///   `packages/foo/lib/bar.dart` -> `package:foo/bar.dart`
  ///   `packages/foo/bar.dart` -> `package:foo/bar.dart`
  static String? packagePathToPackageUri(String path) {
    if (!path.startsWith('packages/')) return null;
    final pathWithoutLib = removeLibSegment(path);
    return 'package:${pathWithoutLib.substring('packages/'.length)}';
  }

  /// Canonicalizes a `packages/` server path using the provided [LoadStrategy].
  ///
  /// Converts `packages/foo/lib/bar.dart` or `packages/foo/bar.dart` to the
  /// load strategy's canonical server path. Otherwise returns [path].
  static String canonicalizePackagePath(
    String path,
    LoadStrategy loadStrategy,
  ) {
    if (!path.startsWith('packages/')) return path;
    final packageUri = packagePathToPackageUri(path);
    if (packageUri != null) {
      final canonicalPath = loadStrategy.serverPathForAppUri(packageUri);
      if (canonicalPath != null) {
        var result = canonicalPath;
        while (result.startsWith('/')) {
          result = result.substring(1);
        }
        return result;
      }
    }
    return path;
  }

  /// Translates package paths between layouts based on asset schemes.
  ///
  /// For example, from [FrontendServerAssetScheme] to [BuildRunnerAssetScheme]:
  ///   `packages/foo/lib/bar.dart` -> `packages/foo/bar.dart`
  /// From [BuildRunnerAssetScheme] to [FrontendServerAssetScheme]:
  ///   `packages/foo/bar.dart` -> `packages/foo/lib/bar.dart`
  static String translatePackagePath(
    String path, {
    required AssetScheme from,
    required AssetScheme to,
  }) {
    if (from is FrontendServerAssetScheme && to is BuildRunnerAssetScheme) {
      return removeLibSegment(path);
    }
    if (from is BuildRunnerAssetScheme && to is FrontendServerAssetScheme) {
      return addLibSegment(path);
    }
    return path;
  }

  /// Maps module extensions between layouts based on asset schemes.
  ///
  /// For example, from [FrontendServerAssetScheme] to [BuildRunnerAssetScheme]:
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

  /// Maps a Frontend Server suffix ('.dart.lib') to a package:build ('.ddc')
  /// suffix.
  static String translateFesToBuildRunnerPath(String path) {
    final withoutLib = translatePackagePath(
      path,
      from: _fesScheme,
      to: _buildRunnerScheme,
    );
    return translateModuleExtension(
      withoutLib,
      from: _fesScheme,
      to: _buildRunnerScheme,
    );
  }

  /// Maps a package:build (build_runner) path to a Frontend Server path.
  ///
  /// Adds 'lib/' to package paths and replaces Build Runner suffixes with
  /// Frontend Server suffixes (e.g. '.ddc' -> '.dart.lib').
  static String translateBuildRunnerToFesPath(String path) {
    final withLib = translatePackagePath(
      path,
      from: _buildRunnerScheme,
      to: _fesScheme,
    );
    return translateModuleExtension(
      withLib,
      from: _buildRunnerScheme,
      to: _fesScheme,
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
