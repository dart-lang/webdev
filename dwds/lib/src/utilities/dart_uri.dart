// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:io';

// ignore: implementation_imports
import 'package:_fe_analyzer_shared/src/util/libraries_specification.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../loaders/strategy.dart';

/// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
class DartUri {
  DartUri._(this.serverPath);

  /// Accepts various forms of URI and can convert between forms.
  ///
  /// The accepted forms are:
  ///
  ///  - package:packageName/pathUnderLib/file.dart
  ///  - org-dartlang-app:///prefix/path/file.dart, where prefix is ignored.
  ///    e.g. org-dartlang-app:example/hello_world/main.dart,
  ///  - /packages/packageName/foo.dart, the web server form of a package URI,
  ///    e.g. /packages/path/src/utils.dart
  ///  - /path/foo.dart or path/foo.dart, e.g. /hello_world/web/main.dart, where
  ///    path is a web server path and so relative to the directory being
  ///    served, not to the package.
  ///
  /// The optional [serverUri] is a temporary workaround for a bug with construction.
  /// Older SDKs (before D24) gave us a path that didn't include the full path,
  /// e.g. main.dart rather than hello_world/main.dart and src/path.dart rather than
  /// packages/path/src/path.dart. The optional [serverUri] is the full URI of the
  /// JS script. The dirname of that path should give us the missing prefix.
  factory DartUri(String uri, [String serverUri]) {
    var serverPath = globalLoadStrategy.serverPathForAppUri(uri);
    if (serverPath != null) return DartUri._(serverPath);
    if (uri.startsWith('package:')) {
      return DartUri._fromPackageUri(uri, serverUri: serverUri);
    }
    if (uri.startsWith('file:')) return DartUri._fromFileUri(uri);
    if (uri.startsWith('/packages/')) {
      return DartUri._fromRelativePath(uri, serverUri: serverUri);
    }
    if (uri.startsWith('/')) return DartUri._fromRelativePath(uri);
    if (uri.startsWith('http:') || uri.startsWith('https:')) {
      return DartUri(Uri.parse(uri).path);
    }

    throw FormatException('Unsupported URI form', uri);
  }

  /// Construct from a package: URI
  factory DartUri._fromPackageUri(String uri, {String serverUri}) {
    var packagePath = 'packages/${uri.substring("package:".length)}';
    if (serverUri != null) {
      return DartUri._fromRelativePath(
          p.url.join(_dirForServerUri(serverUri), packagePath));
    }
    return DartUri._(packagePath);
  }

  /// Construct from a file: URI
  factory DartUri._fromFileUri(String uri) {
    var libraryName = _resolvedUriToUri[uri];
    if (libraryName != null) return DartUri(libraryName);
    // This is not one of our recorded libraries.
    throw ArgumentError.value(uri, 'uri', 'Unknown library');
  }

  /// Construct from a path, relative to the directory being served.
  factory DartUri._fromRelativePath(String uri, {String serverUri}) {
    uri = uri[0] == '.' ? uri.substring(1) : uri;
    uri = uri[0] == '/' ? uri.substring(1) : uri;

    if (serverUri != null) {
      return DartUri._fromRelativePath(
          p.url.join(_dirForServerUri(serverUri), uri));
    }
    return DartUri._(uri);
  }

  /// The canonical web server path part of the URI.
  ///
  /// This is a relative path, which can be used to fetch the corresponding file
  /// from the server. For example, 'hello_world/main.dart' or
  /// 'packages/path/src/utils.dart'.
  final String serverPath;

  static final _logger = Logger('DartUri');

  /// The way we resolve file: URLs into package: URLs
  static PackageConfig _packageConfig;

  /// The way we resolve dart: URLs into org-dartland-sdk: URLs
  static TargetLibrariesSpecification _librariesSpec;

  /// SDK installation directory.
  ///
  /// Directory where the SDK client code built with is installed,
  ///
  /// For example: `/Users/me/.dart-sdks/2.15.0`
  ///
  /// Used to resolve SDK urls according to vm_service protocol.
  static Uri _sdkDir;

  /// All of the known absolute library paths, indexed by their library URL.
  ///
  /// Examples:
  ///
  /// We are assuming that all library uris are coming from
  /// https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md#getscripts)
  /// and can be translated to their absolute paths and back.
  ///
  /// dart:html <->
  ///   org-dartlang-sdk:///sdk/lib/html/html.dart
  /// (not supported, issue: https://github.com/dart-lang/webdev/issues/1457)
  ///
  /// org-dartlang-app:///example/hello_world/main.dart <->
  ///   file:///source/webdev/fixtures/_test/example/hello_world/main.dart,
  ///
  /// org-dartlang-app:///example/hello_world/part.dart <->
  ///   file:///source/webdev/fixtures/_test/example/hello_world/part.dart,
  ///
  /// package:path/path.dart <->
  ///   file:///.pub-cache/hosted/pub.dartlang.org/path-1.8.0/lib/path.dart,
  ///
  /// package:path/src/path_set.dart <->
  ///   file:///.pub-cache/hosted/pub.dartlang.org/path-1.8.0/lib/src/path_set.dart,
  static final Map<String, String> _uriToResolvedUri = {};

  /// All of the known libraries, indexed by their absolute file URL.
  static final Map<String, String> _resolvedUriToUri = {};

  /// Returns package, app, or dart uri for a resolved path.
  static String toPackageUri(String uri) => _resolvedUriToUri[uri];

  /// Returns resolved path for a package, app, or dart uri.
  static String toResolvedUri(String uri) => _uriToResolvedUri[uri];

  /// The directory in which we're running.
  ///
  /// We store this here because for tests we may want to act as if we're
  /// running in the directory of a target package, even if the current
  /// directory of the tests is actually the main dwds directory.
  static String currentDirectory = p.current;

  /// The current directory as a file: Uri, saved here to avoid re-computing.
  static String currentDirectoryUri = '${p.toUri(currentDirectory)}';

  /// Record library and script uris to enable resolving library and script paths.
  static Future<void> initialize({Uri sdkDir}) async {
    _sdkDir =
        sdkDir ?? p.toUri(p.dirname(p.dirname(Platform.resolvedExecutable)));

    var librariesPath =
        p.toUri(p.join(_sdkDir.toFilePath(), 'lib', 'libraries.json'));
    var packagesUri = p.toUri(p.join(currentDirectory, '.packages'));

    clear();
    _loadLibrariesConfig(librariesPath);
    return await _loadPackageConfig(packagesUri);
  }

  /// Clear the uri resolution tables.
  static void clear() {
    _resolvedUriToUri.clear();
    _uriToResolvedUri.clear();
  }

  /// Record all of the libraries, indexed by their absolute file: URI.
  static Future<void> recordAbsoluteUris(Iterable<String> libraryUris) async {
    for (var uri in libraryUris) {
      _recordAbsoluteUri(uri);
    }
  }

  /// Returns the dirname for the server URI.
  static String _dirForServerUri(String uri) => p.dirname(Uri.parse(uri).path);

  /// Load the .packages file associated with the running application so we can
  /// resolve file URLs into package: URLs appropriately.
  static Future<void> _loadPackageConfig(Uri uri) async {
    _packageConfig = await loadPackageConfigUri(uri, onError: (e) {
      _logger.warning('Cannot read packages spec: $uri', e);
    });
  }

  /// Load and parse libraries.json spec file.
  /// Used for resolving `dart:` libraries uris.
  static void _loadLibrariesConfig(Uri uri) {
    try {
      var json = File.fromUri(uri).readAsStringSync();
      _librariesSpec =
          LibrariesSpecification.parse(uri, json).specificationFor('dartdevc');
    } on LibrariesSpecificationException catch (e, s) {
      _logger.warning('Cannot read libraries spec: $uri', e, s);
    }
  }

  /// Record the library represented by package: or org-dartlang-app: uris
  /// indexed by absolute file: URI.
  static void _recordAbsoluteUri(String libraryUri) {
    var uri = Uri.parse(libraryUri);
    if (uri.scheme.isEmpty && !uri.path.endsWith('.dart')) {
      // ignore non-dart files
      return;
    }

    String libraryPath;
    switch (uri.scheme) {
      case 'dart':
        var libSpec = _librariesSpec?.libraryInfoFor(uri.path);
        libraryPath = libSpec?.uri?.path;
        libraryPath =
            libraryPath?.replaceAll(_sdkDir.path, 'org-dartlang-sdk:///sdk');
        break;
      case 'org-dartlang-app':
      case 'google3':
        // Both currentDirectoryUri and the libraryUri path should have '/'
        // separators, so we can join them as url paths to get the absolute file
        // url.
        libraryPath = p.url.join(currentDirectoryUri, uri.path.substring(1));
        break;
      case 'package':
        libraryPath = _packageConfig?.resolve(uri).toString();
        break;
      default:
        throw ArgumentError.value(libraryUri, 'URI scheme not allowed');
    }

    if (libraryPath != null) {
      _uriToResolvedUri[libraryUri] = libraryPath;
      _resolvedUriToUri[libraryPath] = libraryUri;
    } else {
      _logger.warning('Unresolved uri: $uri');
    }
  }
}
