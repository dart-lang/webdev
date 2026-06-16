// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The path format of the DDC application's served files.
enum AppUriLayout {
  /// Used when compiling and serving directly with Frontend Server.
  /// Preserves 'lib/' segments for package paths (e.g. packages/foo/lib/bar.dart).
  frontendServerOnly,

  /// Used when compiling/serving with package:build.
  /// Omits 'lib/' segments (e.g. packages/foo/bar.dart).
  buildRunner,
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
  /// `org-dartlang-app:///web/web/main.dart` ->`web/main.dart`
  /// `org-dartlang-app:///foo/bar.dart` -> `bar.dart`
  static String? translateAppUriToServerPath(
    String appUrl, {
    required AppUriLayout layout,
  }) {
    final appUri = Uri.parse(appUrl);

    if (appUri.isScheme('package')) {
      final pathSegments = appUri.pathSegments;
      if (pathSegments.isEmpty) {
        throw FormatException('Invalid package URI with empty path: $appUrl');
      }
      return switch (layout) {
        AppUriLayout.frontendServerOnly =>
          'packages/${pathSegments.first}/lib/${pathSegments.skip(1).join('/')}',
        AppUriLayout.buildRunner => 'packages/${appUri.path}',
      };
    }

    if (appUri.isScheme('org-dartlang-app')) {
      final segments = appUri.pathSegments;
      if (segments.isEmpty) {
        throw FormatException(
          'Invalid org-dartlang-app URI with empty path: $appUrl',
        );
      }
      switch (layout) {
        case AppUriLayout.frontendServerOnly:
          return appUri.path.substring(1);
        case AppUriLayout.buildRunner:
          final first = segments.first;
          if (first == 'packages') {
            assert(segments.length >= 3, 'Invalid packages/ URI: $appUrl');
            return segments.join('/');
          }

          final isDuplicated =
              segments.length > 2 &&
              first == segments[1] &&
              (first == 'web' || first == 'test');
          return segments.skip(isDuplicated ? 2 : 1).join('/');
      }
    }

    return null;
  }

  /// Translates a 'lib/' path to a package path.
  ///
  /// DDC generates source maps with relative paths from the generated output.
  /// Files in the root package can resolve to 'lib/' references, so we prepend
  /// `packages/[rootPackageName]/` to resolve them to a package URI. Example:
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
      return 'packages/$rootPackageName/${uri.substring(4)}';
    }
    return uri;
  }

  /// Maps '.dart.lib' (FES suffix) to '.ddc' (package:build suffix).
  static String translateFesToBuildRunnerPath(String path) {
    return path.replaceAll('.dart.lib', '.ddc');
  }
}
