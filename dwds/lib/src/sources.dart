import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart' as source_maps;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';

import 'token_position.dart';

/// Keeps track of the scripts (both Dart and JS) and their source maps.
class Sources {
  Sources(this.mainProxy);

  /// The main service proxy that this is associated with.
  ChromeProxyService mainProxy;

  /// The Chrome debugger connection.
  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// Map from the server URI for Dart scripts to the JS script that is built
  /// from that Dart code. See [DartUri] for details on the URIs.
  Map<String, WipScript> jsScripts = {};

  /// Map from both Dart relative serer URIs to their sourcemap.
  ///
  /// See [DartUri] for more details on URI format.
  final Map<String, source_maps.SingleMapping> _dartSourcemaps = {};

  /// Map from JS absolute server URLs to the sourcemap used
  /// for them.
  final Map<String, source_maps.SingleMapping> _jsSourcemaps = {};

  final _sourceToTokens = <String, Set<TokenPos>>{};

  /// Map from relative dart source path to tokenPosTable as defined in the
  /// Dart VM Service Protocol.
  final _sourceToTokenPosTable = <String, List<List<int>>>{};

  /// Find the source map for a Dart file identified by its (relative) server
  /// URI.
  source_maps.SingleMapping sourcemapForDart(String uri) =>
      _dartSourcemaps[uri];

  /// Find the source map for a JS file identified by its absolute server URI.
  source_maps.SingleMapping sourcemapForJs(String uri) => _jsSourcemaps[uri];

  /// Controller for a stream of events when a source map is loaded.
  final StreamController<String> _sourceMapLoadedController =
      StreamController<String>.broadcast();

  /// Stream of events that a source map has been loaded.
  Stream<String> get sourceMapLoaded => _sourceMapLoadedController.stream;

  /// Called to handle the event that a script has been parsed
  /// and add its sourcemap information.
  Future<Null> scriptParsed(ScriptParsedEvent e) async {
    var script = e.script;
    var sourceMapContents = await sourceMap(script);
    if (sourceMapContents == null) return;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = source_maps.parse(sourceMapContents);
    if (mapping is source_maps.SingleMapping) {
      _jsSourcemaps[script.url] = mapping;
      for (var dartUrl in mapping.urls) {
        var canonical = DartUri(dartUrl).serverUri;
        jsScripts[canonical] = script;
        _dartSourcemaps[canonical] = mapping;
        _sourceMapLoadedController.add(canonical);
      }
      // Create TokenPos for each entry in the source map.
      for (var lineEntry in mapping.lines) {
        for (var entry in lineEntry.entries) {
          var index = entry.sourceUrlId;
          if (index == null) continue;
          var dartUrl = mapping.urls[index];
          var dartLine = entry.sourceLine;
          var dartColumn = entry.sourceColumn;
          var token = TokenPos(dartLine, dartColumn);
          _sourceToTokens.putIfAbsent(dartUrl, () => Set()).add(token);
        }
      }
    }
  }

  /// Returns the tokenPosTable for the provided Dart script path as defined
  /// in:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  List<List<int>> tokenPosTableFor(String scriptPath) {
    // Script paths contained in source maps always contain a leading slash.
    scriptPath = scriptPath.startsWith('/') ? scriptPath : '/$scriptPath';
    var tokenPosTable = _sourceToTokenPosTable[scriptPath];
    if (tokenPosTable != null) return tokenPosTable;
    // Construct the tokenPosTable which is of the form:
    // [lineNumber, (tokenId, columnNumber)*]
    tokenPosTable = <List<int>>[];
    var tokens = _sourceToTokens[scriptPath] ?? {};
    var lineNumberToTokens = <int, Set<TokenPos>>{};
    for (var token in tokens) {
      lineNumberToTokens.putIfAbsent(token.line, () => Set()).add(token);
    }
    for (var lineNumber in lineNumberToTokens.keys) {
      var entry = [lineNumber];
      for (var token in lineNumberToTokens[lineNumber]) {
        entry.addAll([token.id, token.column]);
      }
      tokenPosTable.add(entry);
    }
    _sourceToTokenPosTable[scriptPath] = tokenPosTable;
    return tokenPosTable;
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
    var scriptPath = DartUri(script.url).serverUri;
    var sourcemapPath = p.join(p.dirname(scriptPath), sourceMapUrl);
    var result = await mainProxy.assetHandler(sourcemapPath);
    return result;
  }
}
