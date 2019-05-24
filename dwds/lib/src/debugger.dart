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

  final ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// The scripts and sourcemaps for the application, both JS and Dart.
  Sources sources;

  /// Mapping from Dart script IDs to their ScriptRefs.
  Map<String, ScriptRef> _scriptRefs;

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  final _BreakpointMapping _breakpoints = _BreakpointMapping();

  /// Allocates Dart breakpoint IDs
  int _nextBreakpointId = 1;

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
    // TODO(401): Remove the additional parameter.
    var dartUri = DartUri(dartScript.uri, Uri.parse(mainProxy.uri).path);
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
      ..id = '${_nextBreakpointId++}'
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

  /// Remove a Dart breakpoint.
  Future<void> removeBreakpoint(String breakpointId) async {
    // TODO: Clean up breakpoint mapping and expose this as full API. Right now
    // it's a minimal implementation for cleanup.
    var jsId = _breakpoints.jsId(breakpointId);
    return _removeBreakpoint(jsId);
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

  /// Call the Chrome protocol removeBreakpoint.
  Future<void> _removeBreakpoint(String breakpointId) async {
    var response = await chromeDebugger.sendCommand('Debugger.removeBreakpoint',
        params: {'breakpointId': breakpointId});
    handleErrorIfPresent(response);
  }

  /// Find the [Location] for the given Dart source position.
  ///
  /// The [line] number is 1-based.
  Location locationFor(DartUri uri, int line) {
    var sourcemap = sources.sourcemapForDart(uri.serverPath);
    for (var lineEntry in sourcemap.lines) {
      for (var entry in lineEntry.entries) {
        var index = entry.sourceUrlId;
        if (index == null) continue;
        var dartLine = entry.sourceLine;
        // TODO: Handle cases where a breakpoint can't be set exactly at that
        // line and we have to find the nearest valid position.
        if (dartLine != line) continue;

        var dartColumn = entry.sourceColumn;
        var jsLine = lineEntry.line;
        var jsColumn = entry.column;
        var basicDartUrl = sourcemap.urls[entry.sourceUrlId];
        var dartUrl = DartUri(basicDartUrl, uri.serverPath).serverPath;
        var jsScriptId = sources.jsScripts[dartUrl].scriptId;
        // TODO: Don't hard-code Dart token position to 0.
        return Location(jsScriptId, jsLine + 1, jsColumn + 1, dartUrl, dartLine,
            dartColumn, 0);
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
