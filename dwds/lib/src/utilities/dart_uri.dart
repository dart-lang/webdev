// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:package_resolver/package_resolver.dart';

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

  /// Load the .packages file associated with the running application so we can
  /// resolve file URLs into package: URLs appropriately.
  static Future<void> _loadPackageConfig() async {
    _packageResolver ??= await SyncPackageResolver.loadConfig(
        p.join(currentDirectory, '.packages'));
  }

  /// The way we resolve file: URLs into package: URLs
  static SyncPackageResolver _packageResolver;

  /// All of the known libraries, indexed by their absolute file URL.
  static final Map<String, String> _libraryNamesByPath = {};

  /// Record all of the libraries, indexed by their absolute file: URI.
  static Future<void> recordAbsoluteUris(Iterable<String> libraryUris) async {
    await _loadPackageConfig();
    for (var uri in libraryUris) {
      recordAbsoluteUri(uri);
    }
  }

  /// Record the library represented by package: or org-dartlang-app: uris
  /// indexed by absolute file: URI.
  static void recordAbsoluteUri(String libraryUri) {
    var uri = Uri.parse(libraryUri);
    if (uri.scheme == 'dart' ||
        (uri.scheme == '' && !uri.path.endsWith('.dart'))) {
      /// We ignore dart: libraries, and non-Dart libraries referenced by path.
    } else if (uri.scheme == 'org-dartlang-app') {
      var currentAsFileUri = p.toUri(currentDirectory);
      // The Uri's path will be absolute, remove the leading slash.
      var libraryPath = p.join(currentAsFileUri.path, uri.path.substring(1));
      _libraryNamesByPath[Uri.file(libraryPath).toString()] = libraryUri;
    } else if (uri.scheme == 'package') {
      var libraryPath = _packageResolver.resolveUri(uri);
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
    // TODO(401): Remove serverUri after D24 is stable.
    if (uri.startsWith('package:')) return DartUri._fromPackageUri(uri);
    if (uri.startsWith('org-dartlang-app:')) return DartUri._fromAppUri(uri);
    if (uri.startsWith('file:')) return DartUri._fromFileUri(uri);
    if (uri.startsWith('/packages/')) return DartUri._fromServerPath(uri);
    if (uri.startsWith('/')) return DartUri._fromServerPath(uri);
    if (uri.startsWith('http:') || uri.startsWith('https:')) {
      return DartUri(Uri.parse(uri).path);
    }
    // Work around short paths if we have been provided the context.
    if (serverUri != null) {
      var path = Uri.parse(serverUri).path;
      var dir = p.dirname(path);
      return DartUri._fromServerPath(p.normalize(p.join(dir, uri)));
    }
    throw FormatException('Unsupported URI form', uri);
  }

  /// Construct from a package: URI
  factory DartUri._fromPackageUri(String uri) {
    return DartUri._('packages/${uri.substring("package:".length)}');
  }

  /// Construct from a file: URI
  factory DartUri._fromFileUri(String uri) {
    var libraryName = _libraryNamesByPath[uri];
    if (libraryName != null) return DartUri(libraryName);
    // This is not one of our recorded libraries.
    throw ArgumentError.value(uri, 'uri', 'Unknown library');
  }

  /// Construct from an org-dartlang-app: URI.
  factory DartUri._fromAppUri(String uri) {
    // We ignore the first segment of the path, which is the root
    // from which we're serving.
    // TODO: To be able to convert to an org-dartlang-app: URI we will
    // need to know the root - possibly keep it as a static?
    return DartUri._(Uri.parse(uri).pathSegments.skip(1).join('/').toString());
  }

  DartUri._(this.serverPath);

  /// Construct from a path, relative to the directory being served.
  factory DartUri._fromServerPath(String uri) {
    uri = uri[0] == '.' ? uri.substring(1) : uri;
    uri = uri[0] == '/' ? uri.substring(1) : uri;
    return DartUri._(uri);
  }
}
