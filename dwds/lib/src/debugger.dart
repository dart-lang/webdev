import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';
import 'helpers.dart';
import 'sources.dart';

class Debugger {
  Debugger(this.mainProxy);

  /// The main service proxy that this is associated with.
  ChromeProxyService mainProxy;

  /// The underlying connection to Chrome.
  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// Manages our sources, both JS and Dart.
  Sources sources; 

  /// Mapping from Dart script IDs to their ScriptRefs.
  Map<String, ScriptRef> _scriptRefs;

  /// The breakpoints we have set so far, indexable by either 
  /// Dart or JS ID.
  BreakpointMapping breakpoints = BreakpointMapping();

  Future<Null> initialize() async {
    sources = Sources(mainProxy);
    chromeDebugger.onScriptParsed.listen(sources.scriptParsed);
    await chromeDebugger.enable();
  }

  /// Look up the script by it's id in an isolate.
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

  /// Add a breakpoint at the given position.
  ///
  /// Note that line and column are Dart source locations and one-based.
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    Isolate isolate;
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null)
      isolate = await mainProxy.getIsolate(isolateId) as Isolate;

    var dartScript = await _scriptWithId(isolateId, scriptId);
    var dartUri = DartUri(dartScript.uri);
    var jsScript = sources.jsScripts[dartUri.serverUri];
    var location = locationFor(dartUri, line);

    var jsBreakpointId = await _setBreakpoint(jsScript, location);
    var breakpoint = Breakpoint()
      ..resolved = true
      ..location = (SourceLocation()
        ..script = dartScript
        ..tokenPos = location.dartTokenPos
        ..endTokenPos = location.dartTokenPos);
    breakpoints.noteBreakpoint(js: jsBreakpointId, dart: breakpoint.id);

    mainProxy.streamNotify(
        'Debug',
        Event()
          ..kind = EventKind.kBreakpointAdded
          ..isolate = toIsolateRef(isolate)
          ..breakpoint = breakpoint);
    return breakpoint;
  }

  /// Call the Chrome protocol setBreakpoint and return the breakpoint ID.
  Future<String> _setBreakpoint(WipScript jsScript, Location location) async {
    var response = 
          await chromeDebugger.sendCommand('Debugger.setBreakpoint', params: {
        'location': {
          'scriptId': jsScript.scriptId,
          'lineNumber': location.jsLine,
        }
      });
    handleErrorIfPresent(response);
    return response.result['breakpointId'] as String;
  }

  /// Find the [Location] for the given Dart source position.
  Location locationFor(DartUri uri, int line) {
    var sourcemap = sources.sourcemapForDart(uri.serverUri);
    for (var lineEntry in sourcemap.lines) {
      for (var entry in lineEntry.entries) {
        var index = entry.sourceUrlId;
        if (index == null) continue;
        var dartLine = entry.sourceLine;
        // TODO: Handle cases where a breakpoint can't be set exactly at that
        // line and we have to find the nearest valid position.
        if (dartLine == line) {
          var dartColumn = entry.sourceColumn;
          var jsLine = lineEntry.line;
          var jsColumn = entry.column;
          var basicDartUrl = sourcemap.urls[entry.sourceUrlId];
          var dartUrl = DartUri(basicDartUrl).serverUri;
          var jsScriptId = sources.jsScripts[dartUrl].scriptId;
          // TODO: Don't hard-code Dart token position to 0.
          return Location(jsScriptId, jsLine + 1, jsColumn + 1, dartUrl,
              dartLine, dartColumn, 0);
        }
      }
    }
    return null;
  }
}

/// Keeps track of the correspondence between Dart and JS breakpoint IDs.
class BreakpointMapping {
  final Map<String, String> _byJsId = {};
  final Map<String, String> _byDartId = {};

  void noteBreakpoint({String js, String dart}) {
    _byJsId[js] = dart;
    _byDartId[dart] = js;
  }

  String dartId(String jsId) => _byJsId[jsId];
  
  String jsId(String dartId) => _byDartId[dartId];

  // TODO: Support removing breakpoints
}


/// A source location, with both Dart and JS information.
///
/// Note that line and column numbers here are always 1-based. The  Dart VM
/// Service protocol line/column numbers are one-based, but in JS source maps and
/// the Chrome protocol are zero-based, so they require translation. 
class Location {
  Location(this.jsScriptId, this.jsLine, this.jsColumn, this.dartUri,
      this.dartLine, this.dartColumn, this.dartTokenPos);

  final String jsScriptId;
  final int jsLine;
  final int jsColumn;
  final String dartUri;
  final int dartLine;
  final int dartColumn;
  final int dartTokenPos;
}
