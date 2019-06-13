// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';
import 'helpers.dart';
import 'location.dart';
import 'sources.dart';

class Debugger {
  Debugger(this._mainProxy) : _breakpoints = _Breakpoints(_mainProxy);

  final ChromeProxyService _mainProxy;

  WipDebugger get chromeDebugger => _mainProxy.tabConnection.debugger;

  /// The scripts and sourcemaps for the application, both JS and Dart.
  Sources sources;

  /// Mapping from Dart script IDs to their ScriptRefs.
  Map<String, ScriptRef> _scriptRefs;

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  _Breakpoints _breakpoints;

  /// Allocates Dart breakpoint IDs
  int _nextBreakpointId = 1;

  Stack _pausedStack;

  bool _isStepping = false;

  Future<Success> pause() async {
    _isStepping = false;
    var result = await chromeDebugger.sendCommand('Debugger.pause');
    handleErrorIfPresent(result);
    return Success();
  }

  /// Resumes the debugger.
  ///
  /// If the step parameter is not provided, the program will resume regular
  /// execution.
  ///
  /// If the step parameter is provided, it indicates what form of
  /// single-stepping to use.
  ///
  /// Note that stepping will automatically continue until Chrome is paused at
  /// a location for which we have source information.
  Future<Success> resume(String isolateId,
      {String step, int frameIndex}) async {
    if (isolateId != _mainProxy.isolate.id) {
      throw ArgumentError.value(
          isolateId, 'isolateId', 'Unrecognized isolate id');
    }
    if (frameIndex != null) {
      throw ArgumentError('FrameIndex is currently unsupported.');
    }
    WipResponse result;
    if (step != null) {
      _isStepping = true;
      switch (step) {
        case 'Over':
          result = await chromeDebugger.sendCommand('Debugger.stepOver');
          break;
        case 'Out':
          result = await chromeDebugger.sendCommand('Debugger.stepOut');
          break;
        case 'Into':
          result = await chromeDebugger.sendCommand('Debugger.stepInto');
          break;
        default:
          throw ArgumentError('Unexpected value for step: $step');
      }
    } else {
      _isStepping = false;
      result = await chromeDebugger.sendCommand('Debugger.resume');
    }
    handleErrorIfPresent(result);
    return Success();
  }

  /// Returns the current Dart stack for the paused debugger.
  ///
  /// Returns null if the debugger is not paused.
  Future<Stack> getStack(String isolateId) async {
    if (isolateId != _mainProxy.isolate.id) {
      throw ArgumentError.value(
          isolateId, 'isolateId', 'Unrecognized isolate id');
    }
    return _pausedStack;
  }

  Future<Null> initialize() async {
    sources = Sources(_mainProxy);
    // We must add a listener before enabling the debugger otherwise we will
    // miss events.
    chromeDebugger.onScriptParsed.listen(sources.scriptParsed);

    chromeDebugger.onPaused.listen((e) async {
      if (_mainProxy.isolate == null) return;
      var event = Event()..isolate = toIsolateRef(_mainProxy.isolate);
      var params = e.params;
      var breakpoints = params['hitBreakpoints'] as List;
      if (breakpoints.isNotEmpty) {
        event.kind = EventKind.kPauseBreakpoint;
      } else if (e.reason == 'exception' || e.reason == 'assert') {
        event.kind = EventKind.kPauseException;
      } else {
        // If we don't have source location continue stepping.
        if (_isStepping && _sourceLocation(e) == null) {
          await chromeDebugger.sendCommand('Debugger.stepInto');
          return;
        }
        event.kind = EventKind.kPauseInterrupted;
      }
      var frames = _dartFramesFor(e);
      _pausedStack = Stack()
        ..frames = frames
        ..messages = [];
      if (frames.isNotEmpty) event.topFrame = frames.first;
      _mainProxy.streamNotify('Debug', event);
    });

    chromeDebugger.onResumed.listen((e) {
      if (_mainProxy.isolate == null) return;
      _pausedStack = null;
      _mainProxy.streamNotify(
          'Debug',
          Event()
            ..kind = EventKind.kResume
            ..isolate = toIsolateRef(_mainProxy.isolate));
    });

    handleErrorIfPresent(
        await _mainProxy.tabConnection.page.enable() as WipResponse);
    handleErrorIfPresent(await chromeDebugger.enable() as WipResponse);
  }

  /// Add a breakpoint at the given position.
  ///
  /// Note that line and column are Dart source locations and one-based.
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    Isolate isolate;
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) {
      isolate = await _mainProxy.getIsolate(isolateId) as Isolate;
    }

    var dartScript = await _scriptWithId(isolateId, scriptId);
    // TODO(401): Remove the additional parameter.
    var dartUri = DartUri(
        dartScript.uri, '${Uri.parse(_mainProxy.uri).path}/garbage.dart');
    var location = _locationForDart(dartUri, line);
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
    _mainProxy.streamNotify(
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
      isolate = await _mainProxy.getIsolate(isolateId) as Isolate;
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
    _mainProxy.streamNotify(
        'Debug',
        Event()
          ..kind = EventKind.kBreakpointRemoved
          ..isolate = toIsolateRef(isolate)
          ..breakpoint = bp);
    return _removeBreakpoint(jsId);
  }

  /// Look up the script by id in an isolate.
  Future<ScriptRef> _scriptWithId(String isolateId, String scriptId) async {
    // TODO: Reduce duplication with _scriptRefs in mainProxy.
    if (_scriptRefs == null) {
      _scriptRefs = {};
      var scripts = await _mainProxy.scriptRefs(isolateId);
      for (var script in scripts) {
        _scriptRefs[script.id] = script;
      }
    }
    return _scriptRefs[scriptId];
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
  Location _locationForDart(DartUri uri, int line) => sources
      .locationsForDart(uri.serverPath)
      .firstWhere((location) => location.dartLocation.line == line,
          orElse: () => null);

  /// Find the [Location] for the given JS source position.
  ///
  /// The [line] and [column] are 1-based.
  Location _locationForJs(String scriptId, int line, int column) => sources
      .locationsForJs(scriptId)
      .firstWhere((location) => location.jsLocation.line == line,
          orElse: () => null);

  /// Returns source [Location] for the paused event.
  ///
  /// If we do not have [Location] data for the embedded JS location, null is
  /// returned.
  Location _sourceLocation(DebuggerPausedEvent e) {
    var frame = e.params['callFrames'][0];
    var location = frame['location'];
    var jsLocation = JsLocation.fromZeroBased(location['scriptId'] as String,
        location['lineNumber'] as int, location['columnNumber'] as int);
    return _locationForJs(
        jsLocation.scriptId, jsLocation.line, jsLocation.column);
  }

  /// Translates Chrome callFrames contained in [DebuggerPausedEvent] into Dart
  /// [Frame]s.
  List<Frame> _dartFramesFor(DebuggerPausedEvent e) {
    var dartFrames = <Frame>[];
    var index = 0;
    for (var frame in e.params['callFrames']) {
      var location = frame['location'];
      var functionName = frame['functionName'] as String ?? '';
      functionName = functionName.split('.').last;
      // Chrome is 0 based. Account for this.
      var jsLocation = JsLocation.fromZeroBased(location['scriptId'] as String,
          location['lineNumber'] as int, location['columnNumber'] as int);
      var dartFrame = _frameFor(jsLocation);
      if (dartFrame != null) {
        dartFrame.code.name = functionName.isEmpty ? '<closure>' : functionName;
        dartFrame.index = index++;
        dartFrames.add(dartFrame);
      }
    }
    return dartFrames;
  }

  /// Returns a Dart [Frame] for a [JsLocation].
  Frame _frameFor(JsLocation jsLocation) {
    // TODO(sdk/issues/37240) - ideally we look for an exact location instead
    // of the closest location on a given line.
    Location bestLocation;
    for (var location in sources.locationsForJs(jsLocation.scriptId)) {
      if (location.jsLocation.line == jsLocation.line) {
        bestLocation ??= location;
        if ((location.jsLocation.column - jsLocation.column).abs() <
            (bestLocation.jsLocation.column - jsLocation.column).abs()) {
          bestLocation = location;
        }
      }
    }
    if (bestLocation == null) return null;
    var script =
        _mainProxy.scriptRefFor(bestLocation.dartLocation.uri.serverPath);
    return Frame()
      ..code = (CodeRef()..kind = CodeKind.kDart)
      ..location = (SourceLocation()
        ..tokenPos = bestLocation.tokenPos
        ..script = script)
      ..kind = FrameKind.kRegular;
  }
}

/// Keeps track of the Dart and JS breakpoint Ids that correspond.
class _Breakpoints {
  final Map<String, String> _byJsId = {};
  final Map<String, String> _byDartId = {};

  // TODO(439): We need to resolve the way we talk to other components.
  final ChromeProxyService _mainProxy;

  Isolate get _isolate => _mainProxy.isolate;

  _Breakpoints(this._mainProxy);

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
