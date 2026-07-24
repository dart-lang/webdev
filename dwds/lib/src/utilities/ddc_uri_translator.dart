// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

enum AppUriLayout {
  /// Used when compiling and serving directly with Frontend Server.
  /// Preserves 'lib/' segments for package paths (e.g. packages/foo/lib/bar.dart).
  frontendServerOnly,

  /// Used when compiling/serving with package:build.
  /// Omits 'lib/' segments (e.g. packages/foo/bar.dart).
  buildRunner,

  /// Used when serving Flutter apps.
  /// Omits 'lib/' segments for package paths (e.g. packages/foo/bar.dart).
  flutter,
}

/// Translates paths across DDC, Frontend Server, DWDS, and package:build.
class DdcUriTranslator {
  /// Translates a DDC app URI (any referenceable dart file) into a path
  /// expected by its [layout]'s asset server.
  ///
  /// FES Only Layout:
  /// `package:foo/bar.dart` -> `packages/foo/lib/bar.dart`
  /// `org-dartlang-app:///foo/bar.dart` -> `foo/bar.dart`
  ///
  /// Build Runner Layout:
  /// `package:foo/bar.dart` -> `packages/foo/bar.dart`
  /// `org-dartlang-app:///packages/foo/bar.dart` -> `packages/foo/bar.dart`
  /// `org-dartlang-app:///web/web/main.dart` -> `main.dart` (deduped)
  /// `org-dartlang-app:///web/main.dart` -> `main.dart`
  /// `org-dartlang-app:///foo/bar.dart` -> `bar.dart`
  static String? translateAppUriToServerPath(
    String appUrl, {
    required AppUriLayout layout,
    bool useDebuggerModuleNames = true,
  }) {
    appUrl = appUrl.replaceAll('\\', '/');
    final appUri = Uri.parse(appUrl);
    if (appUri.isScheme('package')) {
      final pathSegments = appUri.pathSegments;
      if (pathSegments.isEmpty) {
        throw FormatException('Invalid package URI with empty path: $appUrl');
      }
      final buildRunnerPath = 'packages/${appUri.path}';
      return switch (layout) {
        AppUriLayout.frontendServerOnly =>
          useDebuggerModuleNames
              ? addLibSegment(buildRunnerPath)
              : buildRunnerPath,
        AppUriLayout.buildRunner || AppUriLayout.flutter => buildRunnerPath,
      };
    }

    if (appUri.isScheme('org-dartlang-app')) {
      final segments = appUri.pathSegments;
      if (segments.isEmpty) {
        throw FormatException('Invalid org-dartlang-app URI: $appUrl');
      }
      switch (layout) {
        case AppUriLayout.frontendServerOnly:
          return useDebuggerModuleNames
              ? addLibSegment(appUri.path.substring(1))
              : removeLibSegment(appUri.path.substring(1));
        case AppUriLayout.buildRunner:
        case AppUriLayout.flutter:
          final first = segments.first;
          if (first == 'packages') {
            if (segments.length < 3) {
              throw FormatException('Invalid package path in app URI: $appUrl');
            }
            return segments.join('/');
          }
          return segments.skip(1).join('/');
      }
    }

    return null;
  }

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
  /// Example: packages/foo/lib/bar.dart packages/foo/bar.dart
  static String removeLibSegment(String serverPath) =>
      _modifyLibSegment(serverPath, add: false);

  /// Translates a served `packages/` path back to a `package:` URI.
  ///
  /// Examples:
  /// - `packages/foo/lib/bar.dart` -> `package:foo/bar.dart`
  /// - `packages/foo/bar.dart` -> `package:foo/bar.dart`
  static String translatePackagesPathToPackageUri(
    String serverPath, {
    AppUriLayout? layout,
  }) {
    if (!serverPath.startsWith('packages/')) return serverPath;
    // If layout is not provided, we assume it might have 'lib/'.
    final pathWithoutLib =
        layout == null || layout == AppUriLayout.frontendServerOnly
        ? removeLibSegment(serverPath)
        : serverPath;
    return pathWithoutLib.replaceFirst('packages/', 'package:');
  }

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
  /// For example, from [AppUriLayout.frontendServerOnly] to
  /// [AppUriLayout.buildRunner]:
  ///   `main.dart.lib` -> `main.ddc`
  ///   `main.dart.lib.js` -> `main.ddc.js`
  static String translateModuleExtension(
    String path, {
    required AppUriLayout from,
    required AppUriLayout to,
  }) {
    if (from == to) return path;
    if (from == AppUriLayout.frontendServerOnly &&
        to == AppUriLayout.buildRunner) {
      return path.replaceAll('.dart.lib', '.ddc');
    }
    if (from == AppUriLayout.buildRunner &&
        to == AppUriLayout.frontendServerOnly) {
      return path.replaceAll('.ddc', '.dart.lib');
    }
    return path;
  }

  /// Maps '.dart.lib' (FES suffix) to '.ddc' (package:build suffix).
  static String translateFesToBuildRunnerPath(String path) {
    return translateModuleExtension(
      path,
      from: AppUriLayout.frontendServerOnly,
      to: AppUriLayout.buildRunner,
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
