// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';
import 'helpers.dart';
import 'location.dart';
import 'sources.dart';

class Debugger {
  Debugger(this.mainProxy);

  /// The main service proxy that this is associated with.
  final ChromeProxyService mainProxy;

  /// The underlying connection to Chrome.
  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// Manages our sources, both JS and Dart.
  Sources sources;

  /// Mapping from Dart script IDs to their ScriptRefs.
  Map<String, ScriptRef> _scriptRefs;

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  final _BreakpointMapping _breakpoints = _BreakpointMapping();

  Future<Null> initialize() async {
    sources = Sources(mainProxy);
    chromeDebugger.onScriptParsed.listen(sources.scriptParsed);
    await chromeDebugger.enable();
  }

  /// Look up the script by id in an isolate.
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
    if (isolateId != null) {
      isolate = await mainProxy.getIsolate(isolateId) as Isolate;
    }

    var dartScript = await _scriptWithId(isolateId, scriptId);
    var dartUri = DartUri(dartScript.uri);
    var jsScript = sources.jsScripts[dartUri.serverPath];
    var location = locationFor(dartUri, line);

    var jsBreakpointId = await _setBreakpoint(jsScript, location);
    var dartBreakpoint = _dartBreakpoint(dartScript, location, isolate);
    _breakpoints.noteBreakpoint(js: jsBreakpointId, dart: dartBreakpoint.id);
    return dartBreakpoint;
  }

  /// Create a Dart breakpoint at [location] in [dartScript].
  Breakpoint _dartBreakpoint(
      ScriptRef dartScript, Location location, Isolate isolate) {
    var breakpoint = Breakpoint()
      ..resolved = true
      ..location = (SourceLocation()
        ..script = dartScript
        ..tokenPos = location.dartTokenPos
        ..endTokenPos = location.dartTokenPos);
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
    var sourcemap = sources.sourcemapForDart(uri.serverPath);
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
          var dartUrl = DartUri(basicDartUrl).serverPath;
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

/// Keeps track of the Dart and JS breakpoint Ids that correspond.
class _BreakpointMapping {
  final Map<String, String> _byJsId = {};
  final Map<String, String> _byDartId = {};

  void noteBreakpoint({String js, String dart}) {
    _byJsId[js] = dart;
    _byDartId[dart] = js;
  }

  String dartId(String jsId) => _byJsId[jsId];

  String jsId(String dartId) => _byDartId[dartId];

  // TODO(https://github.com/dart-lang/webdev/issues/400): Support removing
  // breakpoints
}
