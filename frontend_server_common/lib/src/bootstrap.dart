// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'package:meta/meta.dart';

/// The JavaScript bootstrap script to support in-browser hot restart.
///
/// The [requireUrl] loads our cached RequireJS script file. The [mapperUrl]
/// loads the special Dart stack trace mapper. The [entrypoint] is the
/// actual main.dart file.
///
/// This file is served when the browser requests "main.dart.js" in debug mode,
/// and is responsible for bootstrapping the RequireJS modules and attaching
/// the hot reload hooks.
String generateBootstrapScript({
  @required String requireUrl,
  @required String mapperUrl,
  @required String entrypoint,
}) {
  return '''
"use strict";

// Attach source mapping.
var mapperEl = document.createElement("script");
mapperEl.defer = true;
mapperEl.async = false;
mapperEl.src = "$mapperUrl";
document.head.appendChild(mapperEl);

// Attach require JS.
var requireEl = document.createElement("script");
requireEl.defer = true;
requireEl.async = false;
requireEl.src = "$requireUrl";
// This attribute tells require JS what to load as main (defined below).
requireEl.setAttribute("data-main", "main_module.bootstrap");
document.head.appendChild(requireEl);
''';
}

/// Generate a synthetic main module which captures the application's main
/// method.
///
/// RE: Object.keys usage in app.main:
/// This attaches the main entrypoint and hot reload functionality to the window.
/// The app module will have a single property which contains the actual application
/// code. The property name is based off of the entrypoint that is generated, for example
/// the file `foo/bar/baz.dart` will generate a property named approximately
/// `foo__bar__baz`. Rather than attempt to guess, we assume the first property of
/// this object is the module.
String generateMainModule({@required String entrypoint}) {
  return '''/* ENTRYPOINT_EXTENTION_MARKER */

// Create the main module loaded below.
define("main_module.bootstrap", ["$entrypoint", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk.dart.setStartAsyncSynchronously(true);
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  dart_sdk._debugger.registerDevtoolsFormatter();
  let voidToNull = () => (voidToNull = dart_sdk.dart.constFn(dart_sdk.dart.fnType(dart_sdk.core.Null, [dart_sdk.dart.void])))();

  // See the generateMainModule doc comment.
  var child = {};
  child.main = app[Object.keys(app)[0]].main;

  /* MAIN_EXTENSION_MARKER */
  child.main();
});
''';
}
