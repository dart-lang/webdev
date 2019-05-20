import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart' as source_maps;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';

/// Keeps track of the scripts (both Dart and JS) and their source maps.
class Sources {
  Sources(this.mainProxy);

  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// Map from canonical Dart URL) to the JS script that is built from that
  /// Dart code.
  ///
  /// The Dart URLs are relative, see [DartUri].
  Map<String, WipScript> jsScripts = {};

  /// Map from both Dart and JS URLs to the sourcemap used
  /// for them.
  ///
  /// Note that the keys are either Dart or JS. The JS URIs are absolute.
  // TODO: Having two different sorts of URIs is messy, clean this up.
  Map<String, source_maps.SingleMapping> sourcemaps = {};

  /// Controller for a stream of events when a source map is loaded.
  StreamController<String> sourceMapLoadedController =
      StreamController<String>.broadcast();

  /// Stream of events that a source map has been loaded.
  Stream<String> get sourceMapLoaded => sourceMapLoadedController.stream;

  /// Called to handle the event that a script has been parsed
  /// and add its sourcemap information.
  Future<Null> scriptParsed(ScriptParsedEvent e) async {
    var script = e.script;
    var sourceMapContents = await sourceMap(script);
    if (sourceMapContents == null) return;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = source_maps.parse(sourceMapContents);
    if (mapping is source_maps.SingleMapping) {
      // We're indexing them by both JS and Dart URI, so we can look them up
      // either way. But it's messy.
      sourcemaps[script.url] = mapping;
      for (var dartUrl in mapping.urls) {
        var canonical = DartUri(dartUrl).serverUri;
        jsScripts[canonical] = script;
        sourcemaps[canonical] = mapping;
        sourceMapLoadedController.add(canonical);
      }
    }
  }

  /// Return a Future that completes once the source map for [url] has been
  /// loaded.
  Future<String> waitForSourceMap(String url) {
    var completer = Completer<String>();
    StreamSubscription listener;
    listener = sourceMapLoaded.listen((loadedUrl) {
      if (url == loadedUrl) completer.complete(url);
      listener.cancel();
    });
    return completer.future;
  }

  /// The source map for a DDC-compiled JS [script].
  Future<String> sourceMap(WipScript script) async {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null || !sourceMapUrl.endsWith('.ddc.js.map')) {
      return null;
    }
    // TODO: Clean up.
    var fullPath = p.join(p.dirname(Uri.parse(script.url).path), sourceMapUrl);
    fullPath = fullPath.substring(1); // Remove leading /
    var sourceMapContents = await mainProxy.assetHandler(fullPath);
    return sourceMapContents;
  }
}
