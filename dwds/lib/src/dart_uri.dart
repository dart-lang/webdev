// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
class DartUri {
  /// Accepts various forms of URI and can convert between forms.
  ///
  /// The accepted forms are:
  ///
  ///  - package:packageName/pathUnderLib/file.dart
  ///  - org-dartlang-app:///prefix/path/file.dart, where prefix is ignored.
  ///    e.g. org-dartlang-app:example/hello_world/main.dart,
  ///  - /packages/packageName/foo.dart, the web server form of a package URI,
  ///    e.g. /packages/path/src/utils.dart
  ///  - /path/foo.dart, e.g. hello_world/web/main.dart, where path is a web
  ///    server path and so relative to the directory being served, not to the
  ///    package.
  ///
  /// Note that there was a bug where older SDKs might provide
  factory DartUri(String uri) {
    if (uri.startsWith('package:')) return DartUri._fromPackageUri(uri);
    if (uri.startsWith('org-dartlang-app:')) return DartUri._fromAppUri(uri);
    if (uri.startsWith('/packages/')) return DartUri._fromPackagesPath(uri);
    if (uri.startsWith('/')) return DartUri._fromPath(uri);
    throw FormatException('Unsupported URI form', uri);
  }

  /// Construct from a package: URI
  DartUri._fromPackageUri(String uri) {
    serverUri = 'packages/${uri.substring("package:".length)}';
  }

  /// Construct from an org-dartlang-app: URI.
  DartUri._fromAppUri(String uri) {
    // We ignore the first segment of the path, which is the root
    // from which we're serving.
    // TODO: To be able to convert to an org-dartlang-app: URI we will
    // need to know the root - possibly keep it as a static?
    serverUri = Uri.parse(uri).pathSegments.skip(1).join('/').toString();
  }

  /// Construct from a path of the form /packages/packageName/foo.dart
  DartUri._fromPackagesPath(this.serverUri);

  /// Construct from an ordinary path, relative to the directory being served.
  DartUri._fromPath(String uri) {
    serverUri = uri[0] == '/' ? uri.substring(1) : uri;
  }

  /// The canonical web server form of the URI.
  ///
  /// This is a relative URI, which can be used to fetch the corresponding file
  /// from the server. For example, 'hello_world/main.dart' or
  /// 'packages/path/src/utils.dart'.
  String serverUri;
}
