/// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
class DartUri {
  /// Expects a URI of the form /hello_world/main.dart or /packages/...
  DartUri.fromSourcemap(String dartFile) {
  // TODO: What's the exact form of /packages URLS? Do we need to 
  // compensate for the lib directory?
    if (dartFile.startsWith('/packages/')) {
      dartForm = 'package:${dartFile.substring("/packages/".length)}';
    } else {
      dartForm = _noLeadingSlash(dartFile);
    }
  }

  /// Expects a Dart URI, which will either be package: or app-dartlang-org:
  DartUri.fromDartScheme(String dartUri) {
    if (dartUri.startsWith('package:')) {
      dartForm = dartUri;  // ### Is this right? OR do we want packages/
    } else if (dartUri.startsWith('app-dartlang-org:')) {
      // Take the path portion and remove the first segment.
      dartForm = Uri.parse(dartUri).pathSegments.skip(1).join('/').toString();
    } else {
      throw FormatException('Unsupported Uri scheme', dartUri);
    }
  }

  /// Make a path relative by removing the leading slash if present.
  String _noLeadingSlash(String s) => s[0] == '/' ? s.substring(1) : s;

  String get uri => dartForm;

  /// The canonical Dart form of the URI.
  ///
  /// This is a relative URI, which can be used to fetch the corresponding file
  /// from the server. For example, 'hello_world/main.dart'
  String dartForm;

  @override
  String toString() => dartForm;
}