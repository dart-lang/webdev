// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';

typedef UrlEncoder = Future<String> Function(String url);

/// A reader for Dart sources and related source maps.
abstract class AssetReader {
  /// Returns the contents for a source map at the provided server path, or
  /// null if the resource does not exist.
  Future<String?> sourceMapContents(String serverPath);

  /// Returns the contents for a dart source at the provided server path, or
  /// null if the resource does not exist.
  Future<String?> dartSourceContents(String serverPath);

  /// Returns the contents for the merged metadata output at the provided path,
  /// or null if the resource does not exist.
  Future<String?> metadataContents(String serverPath);

  /// Closes connections
  Future<void> close();
}

class PackageUriMapper {
  final _logger = Logger('PackageUriMapper');
  final PackageConfig packageConfig;

  static Future<PackageUriMapper> create(FileSystem fileSystem, Uri packageConfigFile) async {  
    final packageConfig = await loadPackageConfig(fileSystem.file(packageConfigFile));
    return PackageUriMapper(packageConfig);
  }

  PackageUriMapper(this.packageConfig);

  // TODO: use package directories instead of package names
  // Note: needs to be the same as `urlForComponentUri` in javascript_bundle.dart in SDK
  String? packageUriToServerPath(Uri packageUri) {
    if (packageUri.isScheme('package')) {
      final Uri? resolvedUri = packageConfig.resolve(packageUri);
      final Package? package = packageConfig.packageOf(resolvedUri!);
      final Uri root = package!.root;
      final String relativeUrl = resolvedUri.toString().replaceFirst('$root', '');
      final relativeRoot = _getRelativeRoot(root);
      _logger.info('XXX package: ${package.name} ($relativeRoot)}');
      final String ret = 'packages/$relativeRoot/$relativeUrl';
      return ret;
    } 
    _logger.severe('Expected package uri, but found $packageUri');
    return null;
  }

  // Needs to match the code above
  Uri? serverPathToResolvedUri(String serverPath) {
    serverPath = stripLeadingSlashes(serverPath);
    final segments = serverPath.split('/');
    if (segments.first == 'packages') {
      final String relativeRoot = segments.skip(1).first;
      _logger.info('XXX package root:  $relativeRoot');

      final String relativeUrl = segments.skip(2).join('/');
      _logger.info('XXX relativeUrl:  $relativeUrl');

      final Package package = packageConfig.packages.firstWhere((Package p) => _getRelativeRoot(p.root) == relativeRoot);
      _logger.info('XXX package:  ${package.name}($relativeRoot)');

      final Uri resolvedUri = package.root.resolve(relativeUrl);
      _logger.info('XXX Server path: $serverPath -> $resolvedUri');

      return resolvedUri;
    }
    return null;
  } 

  String? _getRelativeRoot(Uri root) {
    final segments = root.pathSegments;
    if (segments.isNotEmpty && segments.last.isEmpty) {
      final subset = segments.getRange(0, segments.length-1);
      return subset.isNotEmpty? subset.last: null;
    }
    return segments.isNotEmpty? segments.last: null;
  }
}

String stripLeadingSlashes(String path) {
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  return path;
}