import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart' as source_maps;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'chrome_proxy_service.dart';
import 'helpers.dart';

/// The URI for a particular Dart file, able to canonicalize from various
/// different representations.
class DartUri {
  /// Expects a URI of the form /hello_world/main.dart or /packages/...
  DartUri.fromSourcemap(String dartFile) {
  // TODO: What's the exact form of /packages URLS? Do we need to 
  // compensate for the lib directory?
    if (dartFile.startsWith('/packages/')) {
      dartForm = 'package:${dartFile.substring("/packages/".length)}';
      // ### this is wrong, need to add /lib
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

/// Keeps track of the scripts (both Dart and JS) and their source maps.
class SourceMaps {
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
  Future<Null> _scriptParsed(ScriptParsedEvent e) async {
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
        var canonical = DartUri.fromSourcemap(dartUrl).uri;
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

  /// The source map for a JS [script].
  Future<String> sourceMap(WipScript script) async {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null || sourceMapUrl.isEmpty) {
      return null;
    }
    var absolute = p.join(p.dirname(script.url), sourceMapUrl);
    var sourceMapContents = await mainProxy.assetHandler(absolute);
    return sourceMapContents;
  }
}

class Debugger {
  Debugger(this.mainProxy);

  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  SourceMaps sourcemaps = SourceMaps();

  Map<String, ScriptRef> _scriptRefs;

  Future<Null> initialize() async {
    chromeDebugger.onScriptParsed.listen(sourcemaps._scriptParsed);
    await chromeDebugger.enable();
  }

  Future<ScriptRef> _scriptWithId(String isolateId, String scriptId) async {
    // TODO: Reduce duplication with _scriptRefs in mainProxy.
    if (_scriptRefs == null) {
      _scriptRefs = {};
      var scripts = await mainProxy.scriptRefs(isolateId);
      for (var script in scripts) {
        _scriptRefs[script.id] = script;
      }
    }
    return _scriptRefs[scriptId];
  }

  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    Isolate isolate;
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null)
      isolate = await mainProxy.getIsolate(isolateId) as Isolate;

    var dartScript = await _scriptWithId(isolateId, scriptId);
    var dartUri = DartUri.fromScriptRef(dartScript, mainProxy.uriPath);
    var jsScript = sourcemaps.jsScripts[dartUri.uri];
    // #### This is wrong - the sourcemaps are indexed by JS URI.
    var sourcemap =
        sourcemaps.sourcemaps[dartUri.uri]; // #### clean up this api

    var location = jsPosition(sourcemap, line);
    // actually set the breakpoint
    WipResponse result;
    try {
      result =
          await chromeDebugger.sendCommand('Debugger.setBreakpoint', params: {
        'location': {
          'scriptId': jsScript.scriptId,
          'lineNumber': location.jsLine,
        }
      });
    } catch (e) {
      // throw RpcError(102)..data.details = '$e';
      rethrow;
    }
    var jsBreakpointId = result.result['breakpointId'];
    print('set breakpoint, id = $jsBreakpointId');
    var breakpoint = Breakpoint()
      ..resolved = true
      ..location = (SourceLocation()
        ..script = dartScript
        ..tokenPos = location.dartTokenPos
        ..endTokenPos = location.dartTokenPos);

    // _jsBreakpointIdToDartId[jsBreakpointId] = breakpoint.id;
    // _dartBreakpointIdToJsId[breakpoint.id] = jsBreakpointId;

    mainProxy.streamNotify(
        'Debug',
        Event()
          ..kind = EventKind.kBreakpointAdded
          ..isolate = toIsolateRef(isolate)
          ..breakpoint = breakpoint);
    return breakpoint;
  }

// Appears to return a 1-indexed location.
  Location jsPosition(source_maps.SingleMapping sourcemap, int line) {
    for (var lineEntry in sourcemap.lines) {
      for (var entry in lineEntry.entries) {
        var index = entry.sourceUrlId;
        if (index == null) continue;
        // var dartUrl = _dartifiedUrl(p.join(parent, mapping.urls[index]));
        var dartLine = entry.sourceLine;
        if (dartLine == line) {
          var dartColumn = entry.sourceColumn;
          var jsLine = lineEntry.line;
          var jsColumn = entry.column;
          var basicDartUrl = sourcemap.urls[entry.sourceUrlId];
          var dartUrl = DartUri.fromSourcemap(basicDartUrl).uri;
          var jsScriptId = sourcemaps.jsScripts[dartUrl].scriptId;
          return Location(jsScriptId, jsLine + 1, jsColumn + 1, dartUrl,
              dartLine, dartColumn, 0);
        }
      }
    }
    return null;
  }
}

// ### Use jsScript rather than id? Or do we not have the script?
///
///
/// NOTE: Dart VM Service protocol uses 1-based line and column numbers.
/// JS source maps and protocol uses zero-based line and column numbers.
/// This is consistently one-based.
///
class Location {
  Location(this.jsScriptId, this.jsLine, this.jsColumn, this.dartUrl,
      this.dartLine, this.dartColumn, this.dartTokenPos);

  final String jsScriptId;
  final int jsLine;
  final int jsColumn;
  final String dartUrl;
  final int dartLine;
  final int dartColumn;
  final int dartTokenPos;
}
