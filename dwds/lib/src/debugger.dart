// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';
import 'helpers.dart';
import 'location.dart';
import 'sources.dart';

class Debugger {
  Debugger(this.mainProxy) {
    _breakpoints = _Breakpoints(this);
  }

  final ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// The scripts and sourcemaps for the application, both JS and Dart.
  Sources sources;

  /// Mapping from Dart script IDs to their ScriptRefs.
  Map<String, ScriptRef> _scriptRefs;

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  _Breakpoints _breakpoints;

  /// Allocates Dart breakpoint IDs
  int _nextBreakpointId = 1;

  Future<Null> initialize() async {
    sources = Sources(mainProxy);
    // We must add a listener before enabling the debugger otherwise we will
    // miss events.
    chromeDebugger.onScriptParsed.listen(sources.scriptParsed);
    handleErrorIfPresent(
        await mainProxy.tabConnection.page.enable() as WipResponse);
    handleErrorIfPresent(await chromeDebugger.enable() as WipResponse);
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
    var dartUri = DartUri(
        dartScript.uri, '${Uri.parse(mainProxy.uri).path}/garbage.dart');
    var location = locationForDart(dartUri, line);
    // TODO: Handle cases where a breakpoint can't be set exactly at that line.
    if (location == null) return null;
    var jsBreakpointId = await _setBreakpoint(location);
    var dartBreakpoint = _dartBreakpoint(dartScript, location, isolate);
    _breakpoints.noteBreakpoint(js: jsBreakpointId, bp: dartBreakpoint);
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
        ..tokenPos = location.tokenPos);
    mainProxy.streamNotify(
        'Debug',
        Event()
          ..kind = EventKind.kBreakpointAdded
          ..isolate = toIsolateRef(isolate)
          ..breakpoint = breakpoint);
    return breakpoint;
  }

  /// Remove a Dart breakpoint.
  Future<void> removeBreakpoint(String isolateId, String breakpointId) async {
    Isolate isolate;
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) {
      isolate = await mainProxy.getIsolate(isolateId) as Isolate;
    }
    if (breakpointId == null) {
      throw ArgumentError.notNull('breakpointId');
    }
    var jsId = _breakpoints.jsId(breakpointId);
    var bp = _breakpoints.removeBreakpoint(js: jsId, dartId: breakpointId);
    if (bp == null) {
      throw ArgumentError.value(
          breakpointId, 'Breakpoint not found with this id.');
    }
    mainProxy.streamNotify(
        'Debug',
        Event()
          ..kind = EventKind.kBreakpointRemoved
          ..isolate = toIsolateRef(isolate)
          ..breakpoint = bp);
    return _removeBreakpoint(jsId);
  }

  /// Call the Chrome protocol setBreakpoint and return the breakpoint ID.
  Future<String> _setBreakpoint(Location location) async {
    // Location is 0 based according to:
    // https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Location
    var response =
        await chromeDebugger.sendCommand('Debugger.setBreakpoint', params: {
      'location': {
        'scriptId': location.jsLocation.scriptId,
        'lineNumber': location.jsLocation.line - 1,
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
  Location locationForDart(DartUri uri, int line) => sources
      .locationsForDart(uri.serverPath)
      .firstWhere((location) => location.dartLocation.line == line,
          orElse: () => null);

  /// Returns the closest [Location] for the given Dart source position.
  ///
  /// The [line] and [column] are 1-based.
  ///
  /// Can return null if no suitable [Location] is found.
  Location _bestLocationForJs(String scriptId, int line, int column) {
    Location result;
    for (var location in sources.locationsForJs(scriptId)) {
      if (location.jsLocation.line == line) {
        result ??= location;
        if ((location.jsLocation.column - column).abs() <
            (result.jsLocation.column - column).abs()) {
          result = location;
        }
      }
    }
    return result;
  }

  /// Returns a Dart [Frame] for a [JsLocation].
  Frame frameFor(JsLocation jsLocation) {
    var location = _bestLocationForJs(
        jsLocation.scriptId, jsLocation.line, jsLocation.column);
    if (location == null) return null;
    var script = mainProxy.scriptRefFor(location.dartLocation.uri.serverPath);
    return Frame()
      ..code = (CodeRef()..kind = CodeKind.kDart)
      ..location = (SourceLocation()
        ..tokenPos = location.tokenPos
        ..script = script)
      ..kind = FrameKind.kRegular;
  }
}

/// Keeps track of the Dart and JS breakpoint Ids that correspond.
class _Breakpoints {
  // TODO(439): We need to resolve the way we talk to other components.
  Debugger debugger;

  final Map<String, String> _byJsId = {};
  final Map<String, String> _byDartId = {};

  _Breakpoints(this.debugger);

  Isolate get _isolate => debugger.mainProxy.isolate;

  /// Record the breakpoint.
  ///
  /// Either [dartId] or the Dart breakpoint [bp] must be provided.
  void noteBreakpoint({String js, String dartId, Breakpoint bp}) {
    _byJsId[js] = dartId ?? bp?.id;
    _byDartId[dartId ?? bp?.id] = js;
    if (bp != null) {
      _isolate?.breakpoints?.add(bp);
    }
  }

  Breakpoint removeBreakpoint({String js, String dartId, Breakpoint bp}) {
    _byJsId.remove(js);
    _byDartId.remove(dartId ?? bp?.id);
    Breakpoint dartBp;
    // TODO: Do something better than the default throw when it's not found.
    dartBp = bp ??
        _isolate.breakpoints
            .firstWhere((b) => b.id == dartId, orElse: () => null);
    _isolate?.breakpoints?.remove(dartBp);
    return dartBp;
  }

  String dartId(String jsId) => _byJsId[jsId];

  String jsId(String dartId) => _byDartId[dartId];

  // TODO(https://github.com/dart-lang/webdev/issues/400): Support removing
  // breakpoints
}
