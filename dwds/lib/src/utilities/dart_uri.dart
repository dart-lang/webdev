// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../loaders/strategy.dart';

/// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
class DartUri {
  /// The canonical web server path part of the URI.
  ///
  /// This is a relative path, which can be used to fetch the corresponding file
  /// from the server. For example, 'hello_world/main.dart' or
  /// 'packages/path/src/utils.dart'.
  final String serverPath;

  /// The directory in which we're running.
  ///
  /// We store this here because for tests we may want to act as if we're
  /// running in the directory of a target package, even if the current
  /// directory of the tests is actually the main dwds directory.
  static String currentDirectory = p.current;

  /// The current directory as a file: Uri, saved here to avoid re-computing.
  static String currentDirectoryUri = '${p.toUri(currentDirectory)}';

  /// Load the .packages file associated with the running application so we can
  /// resolve file URLs into package: URLs appropriately.
  static Future<void> _loadPackageConfig(Uri uri) async {
    _packageConfig ??= await loadPackageConfigUri(uri);
  }

  // Note that we join using the platform separator, since currentDirectory is a
  // platform path, not a URI path. Then the toUri should convert them.
  static Uri get _packagesUri => p.toUri(p.join(currentDirectory, '.packages'));

  /// Whether the `.packages` file exists.
  static bool _packagesExist;

  static bool get _shouldRecord =>
      _packagesExist ??= File.fromUri(_packagesUri).existsSync();

  /// The way we resolve file: URLs into package: URLs
  static PackageConfig _packageConfig;

  /// All of the known libraries, indexed by their absolute file URL.
  static final Map<String, String> _libraryNamesByPath = {};

  /// Record all of the libraries, indexed by their absolute file: URI.
  static Future<void> recordAbsoluteUris(Iterable<String> libraryUris) async {
    if (_shouldRecord) {
      await _loadPackageConfig(_packagesUri);
      _libraryNamesByPath.clear();
      for (var uri in libraryUris) {
        _recordAbsoluteUri(uri);
      }
    }
  }

  /// Record the library represented by package: or org-dartlang-app: uris
  /// indexed by absolute file: URI.
  static void _recordAbsoluteUri(String libraryUri) {
    var uri = Uri.parse(libraryUri);
    if (uri.scheme == 'dart' ||
        (uri.scheme == '' && !uri.path.endsWith('.dart'))) {
      // We ignore dart: libraries, and non-Dart libraries referenced by path.
      // e.g. main.dart.bootstrap
      // TODO(alanknight): These should not be showing up in the library list,
      // fix _getLibraryRefs and then remove this check.
    } else if (uri.scheme == 'org-dartlang-app' || uri.scheme == 'google3') {
      // Both currentDirectoryUri and the libraryUri path should have '/'
      // separators, so we can join them as url paths to get the absolute file
      // url.
      var libraryPath =
          p.url.join('$currentDirectoryUri', uri.path.substring(1));
      _libraryNamesByPath[libraryPath] = libraryUri;
    } else if (uri.scheme == 'package') {
      var libraryPath = _packageConfig.resolve(uri);
      _libraryNamesByPath['$libraryPath'] = libraryUri;
    } else {
      throw ArgumentError.value(libraryUri, 'URI scheme not allowed');
    }
  }

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

  /// Returns the dirname for the server URI.
  static String _dirForServerUri(String uri) => p.dirname(Uri.parse(uri).path);

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
    var libraryName = _libraryNamesByPath[uri];
    if (libraryName != null) return DartUri(libraryName);
    // This is not one of our recorded libraries.
    throw ArgumentError.value(uri, 'uri', 'Unknown library');
  }

  DartUri._(this.serverPath);

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
}
