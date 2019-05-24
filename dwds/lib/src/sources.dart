// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';

/// The scripts and sourcemaps for the application, both JS and Dart.
class Sources {
  Sources(this.mainProxy);

  final ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// Map from the server URI for Dart scripts to the JS script that is built
  /// from that Dart code.
  ///
  /// See [DartUri] for details on the URIs.
  final jsScripts = <String, WipScript>{};

  /// Map from both Dart relative server URIs to their sourcemap.
  ///
  /// See [DartUri] for more details on URI format.
  final _dartSourcemaps = <String, SingleMapping>{};

  /// Map from JS absolute server URLs to the sourcemap used
  /// for them.
  final _jsSourcemaps = <String, SingleMapping>{};

  /// Find the source map for a Dart file identified by its (relative) server
  /// URI.
  SingleMapping sourcemapForDart(String uri) => _dartSourcemaps[uri];

  /// Find the source map for a JS file identified by its absolute server URI.
  SingleMapping sourcemapForJs(String uri) => _jsSourcemaps[uri];

  /// Controller for a stream of events when a source map is loaded.
  final _sourceMapLoadedController = StreamController<String>.broadcast();

  /// Stream of events that a source map has been loaded.
  Stream<String> get sourceMapLoaded => _sourceMapLoadedController.stream;

  /// Called to handle the event that a script has been parsed
  /// and add its sourcemap information.
  Future<Null> scriptParsed(ScriptParsedEvent e) async {
    var script = e.script;
    var sourceMapContents = await sourceMap(script);
    if (sourceMapContents == null) return;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = parse(sourceMapContents);
    if (mapping is SingleMapping) {
      _jsSourcemaps[script.url] = mapping;
      for (var dartUrl in mapping.urls) {
        // TODO(401): Remove the additional parameter after D24 is stable.
        var canonical = DartUri(dartUrl, script.url).serverPath;
        jsScripts[canonical] = script;
        _dartSourcemaps[canonical] = mapping;
        _sourceMapLoadedController.add(canonical);
      }
    }
  }

  /// Waits until the source map for the Dart file [uri] has been loaded.
  Future<void> waitForSourceMap(String uri) async =>
      sourcemapForDart(uri) ??
      sourceMapLoaded.firstWhere((loadedUri) => uri == loadedUri);

  /// The source map for a DDC-compiled JS [script].
  Future<String> sourceMap(WipScript script) {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null || !sourceMapUrl.endsWith('.ddc.js.map')) {
      return null;
    }
    var scriptPath = DartUri(script.url).serverPath;
    var sourcemapPath = p.join(p.dirname(scriptPath), sourceMapUrl);
    return mainProxy.assetHandler(sourcemapPath);
  }
}
