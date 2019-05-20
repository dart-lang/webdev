/// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
class DartUri {
  /// Accepts various forms of URI and can convert between forms.
  ///
  /// The accepted forms are:
  ///
  ///  - package:packageName/pathUnderLib
  ///  - org-dartlang-app:///prefix/possibleAppPrefix/path/foo.dart, where
  ///    prefix is ignored
  ///  - /packages/packageName/foo.dart, e.g. package:path/src/utils.dart
  ///  - /possibleAppPrefix/path/foo.dart, where path is under /web. e.g.
  ///    hello_world/main.dart
  factory DartUri(String uri) {
    if (uri.startsWith('package:')) return DartUri._fromPackageUri(uri);
    if (uri.startsWith('org-dartlang-app:')) return DartUri._fromAppUri(uri);
    if (uri.startsWith('/packages/')) return DartUri._fromPackagesPath(uri);
    if (uri.startsWith('/')) return DartUri._fromPath(uri);
    throw FormatException('Unsupported URI form', uri);
  }

  /// Construct from a package: URI
  DartUri._fromPackageUri(String uri) {
    serverUri = '/packages/${uri.substring("package:".length)}';
  }

  /// Construct from an org-dartlang-app: URI.
  DartUri._fromAppUri(String uri) {
    // We ignore the first segment of the path.
    serverUri = Uri.parse(uri).pathSegments.skip(1).join('/').toString();
  }

  /// Construct from a path of the form /packages/packageName/foo.dart
  DartUri._fromPackagesPath(this.serverUri);

  /// Construct from an ordinary path, expected to be under /web.
  DartUri._fromPath(String uri) {
    serverUri = uri[0] == '/' ? uri.substring(1) : uri;
  }

  /// The canonical web server form of the URI.
  ///
  /// This is a relative URI, which can be used to fetch the corresponding file
  /// from the server. For example, 'hello_world/main.dart' or
  /// '/packages/path/src/utils.dart'.
  String serverUri;
}
