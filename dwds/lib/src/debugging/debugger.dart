// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../dwds.dart' show LogWriter;
import '../handlers/asset_handler.dart';
import '../services/chrome_proxy_service.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/objects.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'dart_scope.dart';
import 'location.dart';
import 'remote_debugger.dart';
import 'sources.dart';

/// Converts from ExceptionPauseMode strings to [PauseState] enums.
///
/// Values defined in:
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#method-setPauseOnExceptions
const _pauseModePauseStates = {
  'none': PauseState.none,
  'all': PauseState.all,
  'unhandled': PauseState.uncaught,
};

class Debugger extends Domain {
  final AssetHandler _assetHandler;
  final LogWriter _logWriter;
  final RemoteDebugger _remoteDebugger;

  /// The root URI from which the application is served.
  final String _root;
  final StreamNotify _streamNotify;

  Debugger._(
    this._assetHandler,
    this._remoteDebugger,
    this._streamNotify,
    AppInspectorProvider provider,
    // TODO(401) - Remove.
    this._root,
    this._logWriter,
  )   : _breakpoints = _Breakpoints(provider),
        super(provider);

  /// The scripts and sourcemaps for the application, both JS and Dart.
  Sources sources;

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  final _Breakpoints _breakpoints;

  /// Allocates Dart breakpoint IDs
  int _nextBreakpointId = 1;

  Stack _pausedStack;

  PauseState _pauseState = PauseState.none;

  String get pauseState => _pauseModePauseStates.entries
      .firstWhere((entry) => entry.value == _pauseState)
      .key;

  /// The JS frames corresponding to [_pausedStack].
  ///
  /// The most important thing here is that frames are identified by
  /// frameIndex in the Dart API, but by frame Id in Chrome, so we need
  /// to keep the JS frames and their Ids around.
  // TODO(alanknight): It would be nice to keep these as CallFrame instances,
  // but they don't map enough of the data yet.
  List<Map<String, dynamic>> _pausedJsStack;

  bool _isStepping = false;

  Future<Success> pause() async {
    _isStepping = false;
    var result = await _remoteDebugger.sendCommand('Debugger.pause');
    handleErrorIfPresent(result);
    return Success();
  }

  Future<Success> setExceptionPauseMode(String isolateId, String mode) async {
    checkIsolate(isolateId);
    _pauseState = _pauseModePauseStates[mode.toLowerCase()] ??
        (throw ArgumentError.value('mode', 'Unsupported mode `$mode`'));
    await _remoteDebugger.setPauseOnExceptions(_pauseState);
    return Success();
  }

  /// Resumes the debugger.
  ///
  /// Step parameter options:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#resume
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
    checkIsolate(isolateId);
    if (frameIndex != null) {
      throw ArgumentError('FrameIndex is currently unsupported.');
    }
    WipResponse result;
    if (step != null) {
      _isStepping = true;
      switch (step) {
        case 'Over':
          result = await _remoteDebugger.sendCommand('Debugger.stepOver');
          break;
        case 'Out':
          result = await _remoteDebugger.sendCommand('Debugger.stepOut');
          break;
        case 'Into':
          result = await _remoteDebugger.sendCommand('Debugger.stepInto');
          break;
        default:
          throw ArgumentError('Unexpected value for step: $step');
      }
    } else {
      _isStepping = false;
      result = await _remoteDebugger.sendCommand('Debugger.resume');
    }
    handleErrorIfPresent(result);
    return Success();
  }

  /// Returns the current Dart stack for the paused debugger.
  ///
  /// Returns null if the debugger is not paused.
  Future<Stack> getStack(String isolateId) async {
    checkIsolate(isolateId);
    return _pausedStack;
  }

  static Future<Debugger> create(
    AssetHandler assetHandler,
    RemoteDebugger remoteDebugger,
    StreamNotify streamNotify,
    AppInspectorProvider appInspectorProvider,
    String root,
    LogWriter logWriter,
  ) async {
    var debugger = Debugger._(
      assetHandler,
      remoteDebugger,
      streamNotify,
      appInspectorProvider,
      // TODO(401) - Remove.
      root,
      logWriter,
    );
    await debugger._initialize();
    return debugger;
  }

  Future<Null> _initialize() async {
    sources = Sources(_assetHandler, _remoteDebugger, _logWriter);
    // We must add a listener before enabling the debugger otherwise we will
    // miss events.
    // Allow a null debugger/connection for unit tests.
    _remoteDebugger?.onScriptParsed?.listen(sources.scriptParsed);
    _remoteDebugger?.onPaused?.listen(_pauseHandler);
    _remoteDebugger?.onResumed?.listen(_resumeHandler);

    handleErrorIfPresent(await _remoteDebugger?.sendCommand('Page.enable'));
    handleErrorIfPresent(await _remoteDebugger?.enable() as WipResponse);
  }

  /// Resumes the Isolate from start.
  ///
  /// The JS VM is technically not paused at the start of the Isolate so there
  /// will not be a corresponding [DebuggerResumedEvent].
  Future<void> resumeFromStart() => _resumeHandler(null);

  /// Notify the debugger the [Isolate] is paused at the application start.
  void notifyPausedAtStart() async {
    _pausedStack = Stack(frames: [], messages: []);
  }

  /// Add a breakpoint at the given position.
  ///
  /// Note that line and column are Dart source locations and one-based.
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    var isolate = checkIsolate(isolateId);
    var dartScript = await inspector.scriptWithId(scriptId);
    var dartUri = DartUri(dartScript.uri, _root);
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
    _streamNotify(
        'Debug',
        Event(
            kind: EventKind.kBreakpointAdded,
            timestamp: DateTime.now().millisecondsSinceEpoch)
          ..isolate = inspector.isolateRef
          ..breakpoint = breakpoint);
    return breakpoint;
  }

  /// Remove a Dart breakpoint.
  Future<Success> removeBreakpoint(
      String isolateId, String breakpointId) async {
    checkIsolate(isolateId);
    if (breakpointId == null) {
      throw ArgumentError.notNull('breakpointId');
    }
    var jsId = _breakpoints.jsId(breakpointId);
    var bp = _breakpoints.removeBreakpoint(js: jsId, dartId: breakpointId);
    if (bp == null) {
      throw ArgumentError.value(
          breakpointId, 'Breakpoint not found with this id.');
    }
    _streamNotify(
        'Debug',
        Event(
            kind: EventKind.kBreakpointRemoved,
            timestamp: DateTime.now().millisecondsSinceEpoch)
          ..isolate = inspector.isolateRef
          ..breakpoint = bp);
    await _removeBreakpoint(jsId);
    return Success();
  }

  /// Call the Chrome protocol setBreakpoint and return the breakpoint ID.
  Future<String> _setBreakpoint(Location location) async {
    // Location is 0 based according to:
    // https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Location
    var response =
        await _remoteDebugger.sendCommand('Debugger.setBreakpoint', params: {
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
    var response = await _remoteDebugger.sendCommand(
        'Debugger.removeBreakpoint',
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
  /// The [line] number is 1-based.
  Location _locationForJs(String scriptId, int line) => sources
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
    return _locationForJs(jsLocation.scriptId, jsLocation.line);
  }

  /// Translates Chrome callFrames contained in [DebuggerPausedEvent] into Dart
  /// [Frame]s.
  Future<List<Frame>> dartFramesFor(List<Map<String, dynamic>> frames) async {
    var dartFrames = <Frame>[];
    var index = 0;
    for (var frame in frames) {
      var location = frame['location'];
      var functionName = frame['functionName'] as String ?? '';
      functionName = functionName.split('.').last;
      // Chrome is 0 based. Account for this.
      var jsLocation = JsLocation.fromZeroBased(location['scriptId'] as String,
          location['lineNumber'] as int, location['columnNumber'] as int);
      var dartFrame = await _frameFor(jsLocation);
      if (dartFrame != null) {
        dartFrame.code.name = functionName.isEmpty ? '<closure>' : functionName;
        dartFrame.index = index++;
        dartFrame.vars = await variablesFor(
            frame['scopeChain'] as List<dynamic>,
            frame['callFrameId'] as String);
        dartFrames.add(dartFrame);
      }
    }
    return dartFrames;
  }

  /// The variables visible in a frame in Dart protocol [BoundVariable] form.
  Future<List<BoundVariable>> variablesFor(
      List<dynamic> scopeChain, String callFrameId) async {
    // TODO(alanknight): Can these be moved to dart_scope.dart?
    var properties = await visibleProperties(
        scopeList: scopeChain.cast<Map<String, dynamic>>().toList(),
        debugger: this,
        callFrameId: callFrameId);
    var boundVariables = await Future.wait(
        properties.map((property) async => await _boundVariable(property)));
    boundVariables = boundVariables.where((bv) => bv != null).toList();
    boundVariables.sort((a, b) => a.name.compareTo(b.name));
    return boundVariables;
  }

  Future<BoundVariable> _boundVariable(Property property) async {
    // We return one level of properties from this object. Sub-properties are
    // another round trip.
    var instanceRef =
        await inspector.instanceHelper.instanceRefFor(property.value);
    // Skip null instance refs, which we get for weird objects, e.g.
    // properties that are getter/setter pairs.
    // TODO(alanknight): Handle these properly.
    if (instanceRef == null) return null;
    return BoundVariable()
      ..name = property.name
      ..value = instanceRef
      // TODO(grouma) - Provide an actual token position.
      ..declarationTokenPos = -1;
  }

  /// Calls the Chrome Runtime.getProperties API for the object with [id].
  ///
  /// Note that the property names are JS names, e.g.
  /// Symbol(DartClass.actualName) and will need to be converted.
  Future<List<Property>> getProperties(String id) async {
    var response =
        await _remoteDebugger.sendCommand('Runtime.getProperties', params: {
      'objectId': id,
      'ownProperties': true,
    });
    var jsProperties = response.result['result'];
    var properties = (jsProperties as List)
        .map<Property>((each) => Property(each as Map<String, dynamic>))
        .toList();
    return properties;
  }

  /// Returns a Dart [Frame] for a [JsLocation].
  Future<Frame> _frameFor(JsLocation jsLocation) async {
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
        await inspector?.scriptRefFor(bestLocation.dartLocation.uri.serverPath);
    return Frame()
      ..code = (CodeRef(id: createId(), name: 'DartCode', kind: CodeKind.kDart))
      ..location = (SourceLocation()
        ..tokenPos = bestLocation.tokenPos
        ..script = script)
      ..kind = FrameKind.kRegular;
  }

  /// Handles pause events coming from the Chrome connection.
  Future<void> _pauseHandler(DebuggerPausedEvent e) async {
    var isolate = inspector.isolate;
    if (isolate == null) return;
    Event event;
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    var params = e.params;
    var breakpoints = params['hitBreakpoints'] as List;
    if (breakpoints.isNotEmpty) {
      event = Event(kind: EventKind.kPauseBreakpoint, timestamp: timestamp);
    } else if (e.reason == 'exception' || e.reason == 'assert') {
      event = Event(kind: EventKind.kPauseException, timestamp: timestamp);
    } else {
      // If we don't have source location continue stepping.
      if (_isStepping && _sourceLocation(e) == null) {
        await _remoteDebugger.sendCommand('Debugger.stepInto');
        return;
      }
      event = Event(kind: EventKind.kPauseInterrupted, timestamp: timestamp);
    }
    event.isolate = inspector.isolateRef;
    var jsFrames =
        (e.params['callFrames'] as List).cast<Map<String, dynamic>>();
    var frames = await dartFramesFor(jsFrames);
    _pausedStack = Stack(frames: frames, messages: []);
    _pausedJsStack = jsFrames;
    if (frames.isNotEmpty) event.topFrame = frames.first;
    isolate.pauseEvent = event;
    _streamNotify('Debug', event);
  }

  /// Handles resume events coming from the Chrome connection.
  Future<void> _resumeHandler(DebuggerResumedEvent _) async {
    // We can receive a resume event in the middle of a reload which will
    // result in a null isolate.
    var isolate = inspector?.isolate;
    if (isolate == null) return;
    _pausedStack = null;
    _pausedJsStack = null;
    var event = Event(
        kind: EventKind.kResume,
        timestamp: DateTime.now().millisecondsSinceEpoch)
      ..isolate = inspector.isolateRef;
    isolate.pauseEvent = event;
    _streamNotify('Debug', event);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluateOnCallFrame on
  /// the call frame with index [frameIndex] in the currently saved stack.
  ///
  /// If the program is not paused, so there is no current stack, throws a
  /// [StateError].
  Future<RemoteObject> evaluateJsOnCallFrameIndex(
      int frameIndex, String expression) {
    if (_pausedJsStack == null) {
      throw StateError(
          'Cannot evaluate on a call frame when the program is not paused');
    }
    return evaluateJsOnCallFrame(
        _pausedJsStack[frameIndex]['callFrameId'] as String, expression);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluateOnCallFrame on
  /// the call frame with id [callFrameId].
  Future<RemoteObject> evaluateJsOnCallFrame(
      String callFrameId, String expression) async {
    // TODO(alanknight): Support a version with arguments if needed.
    WipResponse result;
    result = await _remoteDebugger.sendCommand('Debugger.evaluateOnCallFrame',
        params: {'callFrameId': callFrameId, 'expression': expression});
    handleErrorIfPresent(result, evalContents: expression, additionalDetails: {
      'Dart expression': expression,
    });
    return RemoteObject(result.result['result'] as Map<String, dynamic>);
  }
}

/// Keeps track of the Dart and JS breakpoint Ids that correspond.
class _Breakpoints extends Domain {
  final Map<String, String> _byJsId = {};
  final Map<String, String> _byDartId = {};

  _Breakpoints(AppInspectorProvider provider) : super(provider);

  /// Record the breakpoint.
  ///
  /// Either [dartId] or the Dart breakpoint [bp] must be provided.
  void noteBreakpoint({String js, String dartId, Breakpoint bp}) {
    _byJsId[js] = dartId ?? bp?.id;
    _byDartId[dartId ?? bp?.id] = js;
    var isolate = inspector.isolate;
    if (bp != null) {
      isolate?.breakpoints?.add(bp);
    }
  }

  Breakpoint removeBreakpoint({String js, String dartId, Breakpoint bp}) {
    var isolate = inspector.isolate;
    _byJsId.remove(js);
    _byDartId.remove(dartId ?? bp?.id);
    Breakpoint dartBp;
    // TODO: Do something better than the default throw when it's not found.
    dartBp = bp ??
        isolate.breakpoints
            .firstWhere((b) => b.id == dartId, orElse: () => null);
    isolate?.breakpoints?.remove(dartBp);
    return dartBp;
  }

  String dartId(String jsId) => _byJsId[jsId];

  String jsId(String dartId) => _byDartId[dartId];
}
