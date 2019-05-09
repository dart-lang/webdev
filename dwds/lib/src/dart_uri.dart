// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:vm_service_lib/vm_service_lib.dart';

// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
// TODO: Support absolute file and http URLs and org-dartlang-app.
class DartUri {
  /// Expects a URI of the form /hello_world/main.dart or of the form
  /// /packages/...
  ///
  /// Note that these are web server URIs, and are relative to the directory
  /// being served (usually either /web or /test) and not to the root of the
  /// package.
  DartUri.fromSourcemap(String dartFile) {
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
