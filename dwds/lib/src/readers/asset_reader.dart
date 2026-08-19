// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/asset_scheme.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:dwds/src/utilities/web_path_translator.dart';
import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
export 'package:dwds/src/utilities/shared.dart' show stripLeadingSlashes;

/// A reader for Dart sources and related source maps.
abstract class AssetReader {
  /// Base path of the application, for example, set up in the index file:
  ///
  /// ```
  /// <html>
  ///   <head>
  ///     <base href="/abc/">
  ///     <script src="main.dart.js"></script>
  ///   </head>
  /// </html>
  /// ```
  String get basePath;

  /// The asset scheme used by this reader.
  AssetScheme get assetScheme => const FrontendServerAssetScheme();

  /// Returns the contents for a dart source at the provided server path, or
  /// null if the resource does not exist.
  Future<String?> dartSourceContents(String serverPath);

  /// Returns the contents for a source map at the provided server path, or
  /// null if the resource does not exist.
  Future<String?> sourceMapContents(String serverPath);

  /// Returns the contents for the merged metadata output at the provided path,
  /// or null if the resource does not exist.
  Future<String?> metadataContents(String serverPath);

  /// Closes connections
  Future<void> close();
}

abstract class PathResolver {
  final Logger _logger;
  final PackageConfig? packageConfig;
  final bool useDebuggerModuleNames;
  final String? packageRoot;

  PathResolver({
    this.packageConfig,
    this.useDebuggerModuleNames = false,
    this.packageRoot,
    required String loggerName,
  }) : _logger = Logger(loggerName);

  /// Computes the server path for a given application URL.
  ///
  /// Returns `null` if [appUrl] is not supported by the resolver.
  String? appUriToServerPath(String appUrl, {bool? useDebuggerModuleNames});

  /// Computes the application URI (e.g., package: URI) for a given server path.
  ///
  /// Returns `null` if the path cannot be translated to a validapp  URI.
  String? serverPathToAppUri(String serverPath);

  /// Computes the resolved file URI for a given server path.
  ///
  /// Returns `null` if a URI cannot be resolved.
  Uri? serverPathToResolvedUri(String serverPath) {
    serverPath = stripLeadingSlashes(serverPath).replaceAll('\\', '/');
    final segments = serverPath.split('/');
    if (segments.first == 'packages') {
      final config = packageConfig;
      if (config == null) {
        _logger.severe('Cannot resolve packages without packageConfig');
        return null;
      }
      final packagePath = serverPathToAppUri(serverPath);
      if (packagePath == null) return null;
      return config.resolve(Uri.parse(packagePath));
    } else if (packageRoot != null) {
      return Uri.file(p.join(packageRoot!, serverPath));
    }
    _logger.severe(
      'Cannot resolve path without packages/ prefix or packageRoot: $serverPath',
    );
    return null;
  }
}

final class FrontendServerPathResolver extends PathResolver {
  static Future<FrontendServerPathResolver> create(
    FileSystem fileSystem,
    Uri packageConfigFile, {
    bool useDebuggerModuleNames = false,
  }) async {
    final packageConfig = await loadPackageConfig(
      fileSystem.file(packageConfigFile),
    );
    return FrontendServerPathResolver(
      packageConfig: packageConfig,
      useDebuggerModuleNames: useDebuggerModuleNames,
    );
  }

  FrontendServerPathResolver({
    super.packageConfig,
    super.useDebuggerModuleNames = false,
    super.packageRoot,
  }) : super(loggerName: 'FrontendServerPathResolver');

  @override
  String? appUriToServerPath(String appUrl, {bool? useDebuggerModuleNames}) {
    final useDebugger = useDebuggerModuleNames ?? this.useDebuggerModuleNames;
    final appUri = Uri.parse(appUrl);
    // Note: must match `urlForComponentUri` in javascript_bundle.dart in SDK.
    if (appUri.isScheme('package')) {
      // package:foo/bar.dart -> packages/foo/lib/bar.dart (useDebugger)
      // package:foo/bar.dart -> packages/foo/bar.dart (!useDebugger)
      final pathSegments = appUri.pathSegments;
      if (pathSegments.isEmpty) {
        throw FormatException('Invalid package URI with empty path: $appUrl');
      }
      final buildRunnerPath = 'packages/${appUri.path}';
      final path = useDebugger
          ? WebPathTranslator.addLibSegment(buildRunnerPath)
          : buildRunnerPath;
      return path;
    }
    if (appUri.isScheme('org-dartlang-app')) {
      // org-dartlang-app:///web/main.dart -> web/main.dart
      // org-dartlang-app:///packages/foo/bar.dart -> packages/foo/lib/bar.dart (useDebugger)
      // org-dartlang-app:///packages/foo/lib/bar.dart -> packages/foo/bar.dart (!useDebugger)
      final segments = appUri.pathSegments;
      if (segments.isEmpty) {
        throw FormatException('Invalid org-dartlang-app URI: $appUrl');
      }
      final path = useDebugger
          ? WebPathTranslator.addLibSegment(appUri.path.substring(1))
          : WebPathTranslator.removeLibSegment(appUri.path.substring(1));
      return path;
    }
    return null;
  }

  @override
  String? serverPathToAppUri(String serverPath) {
    // packages/foo/lib/bar.dart -> package:foo/bar.dart
    // packages/foo/bar.dart -> package:foo/bar.dart
    // web/main.dart -> web/main.dart
    serverPath = stripLeadingSlashes(serverPath).replaceAll('\\', '/');
    if (!serverPath.startsWith('packages/')) return serverPath;
    return WebPathTranslator.packagePathToPackageUri(serverPath);
  }
}

final class BuildRunnerPathResolver extends PathResolver {
  static Future<BuildRunnerPathResolver> create(
    FileSystem fileSystem,
    Uri packageConfigFile, {
    bool useDebuggerModuleNames = false,
  }) async {
    final packageConfig = await loadPackageConfig(
      fileSystem.file(packageConfigFile),
    );
    return BuildRunnerPathResolver(
      packageConfig: packageConfig,
      useDebuggerModuleNames: useDebuggerModuleNames,
    );
  }

  BuildRunnerPathResolver({
    super.packageConfig,
    super.useDebuggerModuleNames = false,
    super.packageRoot,
  }) : super(loggerName: 'BuildRunnerPathResolver');

  @override
  String? appUriToServerPath(String appUrl, {bool? useDebuggerModuleNames}) {
    final useDebugger = useDebuggerModuleNames ?? this.useDebuggerModuleNames;
    final appUri = Uri.parse(appUrl);
    // Note: must match `urlForComponentUri` in javascript_bundle.dart in SDK.
    if (appUri.isScheme('package')) {
      // package:foo/bar.dart -> packages/foo/bar.dart (useDebugger)
      // package:foo/bar.dart -> /packages/foo/bar.dart (!useDebugger)
      final pathSegments = appUri.pathSegments;
      if (pathSegments.isEmpty) {
        throw FormatException('Invalid package URI with empty path: $appUrl');
      }
      final path = 'packages/${appUri.path}';
      if (!useDebugger && path.startsWith('packages/')) {
        return '/$path';
      }
      return path;
    }

    if (appUri.isScheme('org-dartlang-app')) {
      // org-dartlang-app:///web/main.dart -> main.dart
      // org-dartlang-app:///packages/foo/bar.dart -> packages/foo/bar.dart
      final segments = appUri.pathSegments;
      if (segments.isEmpty) {
        throw FormatException('Invalid org-dartlang-app URI: $appUrl');
      }
      final first = segments.first;
      if (first == 'packages') {
        if (segments.length < 3) {
          throw FormatException('Invalid package path in app URI: $appUrl');
        }
        return segments.join('/');
      }
      return segments.skip(1).join('/');
    }

    return null;
  }

  @override
  String? serverPathToAppUri(String serverPath) {
    // packages/foo/bar.dart -> package:foo/bar.dart
    // web/main.dart -> web/main.dart
    serverPath = stripLeadingSlashes(serverPath).replaceAll('\\', '/');
    if (!serverPath.startsWith('packages/')) return serverPath;
    return serverPath.replaceFirst('packages/', 'package:');
  }
}

final class FlutterPathResolver extends PathResolver {
  FlutterPathResolver({
    super.packageConfig,
    super.useDebuggerModuleNames = false,
    super.packageRoot,
  }) : super(loggerName: 'FlutterPathResolver');

  @override
  String? appUriToServerPath(String appUrl, {bool? useDebuggerModuleNames}) {
    final useDebugger = useDebuggerModuleNames ?? this.useDebuggerModuleNames;
    final isFlutterPackage = appUrl.startsWith('package:');

    if (isFlutterPackage) {
      // package:foo/bar.dart -> packages/foo/bar.dart
      final appUri = Uri.parse(appUrl);
      final pathSegments = appUri.pathSegments;
      if (pathSegments.isEmpty) {
        throw FormatException('Invalid package URI with empty path: $appUrl');
      }
      final path = 'packages/${appUri.path}';
      return path;
    } else {
      final appUri = Uri.parse(appUrl);
      if (appUri.isScheme('org-dartlang-app')) {
        // org-dartlang-app:///web/main.dart -> web/main.dart
        // org-dartlang-app:///packages/foo/bar.dart -> packages/foo/lib/bar.dart (useDebugger)
        // org-dartlang-app:///packages/foo/lib/bar.dart -> packages/foo/bar.dart (!useDebugger)
        final path = useDebugger
            ? WebPathTranslator.addLibSegment(appUri.path.substring(1))
            : WebPathTranslator.removeLibSegment(appUri.path.substring(1));
        return path;
      }
    }
    return null;
  }

  @override
  String? serverPathToAppUri(String serverPath) {
    // packages/foo/lib/bar.dart -> package:foo/bar.dart
    // packages/foo/bar.dart -> package:foo/bar.dart
    // web/main.dart -> web/main.dart
    serverPath = stripLeadingSlashes(serverPath).replaceAll('\\', '/');
    if (!serverPath.startsWith('packages/')) return serverPath;
    return WebPathTranslator.packagePathToPackageUri(serverPath);
  }
}
