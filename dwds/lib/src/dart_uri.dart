import 'package:path/path.dart' as p;
import 'package:vm_service_lib/vm_service_lib.dart';

// The URI for a particular Dart file, able to canonicalize from various
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

  /// Expects a ScriptRef which provides the absolute URI, plus
  /// a URI relative to that.
  DartUri.fromScriptRef(ScriptRef script, String mainUri) {
    // TODO: Longer term the Uri from the ScriptRef should match the WipScript,
    // e.g. hello_world/main.dart. In the short term the ScriptRef just gives us
    // main.dart, so work around it.
    var relative = script.uri;
    dartForm = _noLeadingSlash(p.join(mainUri, relative));
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