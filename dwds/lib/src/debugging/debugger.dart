// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart'
    hide StackTrace;

import '../services/chrome_proxy_service.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/objects.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'dart_scope.dart';
import 'location.dart';
import 'modules.dart';
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

/// Paths to black box in the Chrome debugger.
const _pathsToBlackBox = {'/packages/stack_trace/'};

class Debugger extends Domain {
  static final logger = Logger('Debugger');

  final RemoteDebugger _remoteDebugger;

  /// The root URI from which the application is served.
  final String _root;
  final StreamNotify _streamNotify;
  final Sources _sources;
  final Modules _modules;
  final Locations _locations;

  Debugger._(
    this._remoteDebugger,
    this._streamNotify,
    AppInspectorProvider provider,
    this._sources,
    this._modules,
    this._locations,
    this._root,
  )   : _breakpoints = _Breakpoints(provider),
        super(provider);

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  final _Breakpoints _breakpoints;

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
    RemoteDebugger remoteDebugger,
    StreamNotify streamNotify,
    AppInspectorProvider appInspectorProvider,
    Sources sources,
    Modules modules,
    Locations locations,
    String root,
  ) async {
    var debugger = Debugger._(
      remoteDebugger,
      streamNotify,
      appInspectorProvider,
      sources,
      modules,
      locations,
      root,
    );
    await debugger._initialize();
    return debugger;
  }

  Future<Null> _initialize() async {
    // We must add a listener before enabling the debugger otherwise we will
    // miss events.
    // Allow a null debugger/connection for unit tests.
    runZoned(() {
      _remoteDebugger?.onScriptParsed?.listen((e) {
        _blackBoxIfNecessary(e.script);
        _modules.noteModule(e.script.url, e.script.scriptId);
      });
      _remoteDebugger?.onPaused?.listen(_pauseHandler);
      _remoteDebugger?.onResumed?.listen(_resumeHandler);
    }, onError: (e, StackTrace s) {
      logger.warning('Error handling Chrome event', e, s);
    });

    handleErrorIfPresent(await _remoteDebugger?.sendCommand('Page.enable'));
    handleErrorIfPresent(await _remoteDebugger?.enable() as WipResponse);
  }

  /// Black boxes the Dart SDK and paths in [_pathsToBlackBox].
  Future<void> _blackBoxIfNecessary(WipScript script) async {
    if (script.url.endsWith('dart_sdk.js')) {
      await _blackBoxSdk(script);
    } else if (_pathsToBlackBox.any(script.url.contains)) {
      var content =
          await _sources.readAssetOrNull(DartUri(script.url).serverPath);
      if (content == null) return;
      var lines = content.split('\n');
      await _blackBoxRanges(script.scriptId, [lines.length]);
    }
  }

  /// Black boxes the SDK excluding the range which includes exception logic.
  Future<void> _blackBoxSdk(WipScript script) async {
    var content =
        await _sources.readAssetOrNull(DartUri(script.url).serverPath);
    if (content == null) return;
    var sdkSourceLines = content.split('\n');
    // TODO(grouma) - Find a more robust way to identify this location.
    var throwIndex = sdkSourceLines.indexWhere(
        (line) => line.contains('dart.throw = function throw_(exception) {'));
    if (throwIndex != -1) {
      await _blackBoxRanges(script.scriptId, [throwIndex, throwIndex + 6]);
    }
  }

  Future<void> _blackBoxRanges(String scriptId, List<int> lineNumbers) async {
    try {
      await _remoteDebugger
          .sendCommand('Debugger.setBlackboxedRanges', params: {
        'scriptId': scriptId,
        'positions': [
          {'lineNumber': 0, 'columnNumber': 0},
          for (var line in lineNumbers) {'lineNumber': line, 'columnNumber': 0},
        ]
      });
    } catch (_) {
      // Attempting to set ranges immediately after a refresh can cause issues
      // as the corresponding script will no longer exist. Silently ignore
      // these failures.
    }
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
    checkIsolate(isolateId);
    return _breakpoints.add(scriptId, line, ifAbsent: (String bpId) async {
      var dartScript = await inspector.scriptWithId(scriptId);
      var dartUri = DartUri(dartScript.uri, _root);
      var location = await _locations.locationForDart(dartUri, line);
      // TODO: Handle cases where a breakpoint can't be set exactly at that line.
      if (location == null) {
        // ignore: only_throw_errors
        throw RPCError(
            'addBreakpoint',
            102,
            'The VM is unable to add a breakpoint '
                'at the specified line or function');
      }

      var dartBreakpoint = _dartBreakpoint(dartScript, location, bpId);
      var jsBreakpointId = await _setBreakpoint(location);
      _breakpoints.note(js: jsBreakpointId, bp: dartBreakpoint);
      return dartBreakpoint;
    });
  }

  /// Create a Dart breakpoint at [location] in [dartScript] with [id].
  Breakpoint _dartBreakpoint(
      ScriptRef dartScript, Location location, String id) {
    var breakpoint = Breakpoint()
      ..resolved = true
      ..id = id
      ..location = (SourceLocation()
        ..script = dartScript
        ..tokenPos = location.tokenPos);
    _streamNotify(
        'Debug',
        Event(
            kind: EventKind.kBreakpointAdded,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isolate: inspector.isolateRef)
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
    var bp = _breakpoints.remove(js: jsId, dartId: breakpointId);
    if (bp == null) {
      throw ArgumentError.value(
          breakpointId, 'Breakpoint not found with this id.');
    }
    _streamNotify(
        'Debug',
        Event(
            kind: EventKind.kBreakpointRemoved,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isolate: inspector.isolateRef)
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

  /// Returns source [Location] for the paused event.
  ///
  /// If we do not have [Location] data for the embedded JS location, null is
  /// returned.
  Future<Location> _sourceLocation(DebuggerPausedEvent e) {
    var frame = e.params['callFrames'][0];
    var location = frame['location'];
    var jsLocation = JsLocation.fromZeroBased(location['scriptId'] as String,
        location['lineNumber'] as int, location['columnNumber'] as int);
    return _locations.locationForJs(jsLocation.scriptId, jsLocation.line);
  }

  /// Translates Chrome callFrames contained in [DebuggerPausedEvent] into Dart
  /// [Frame]s.
  Future<List<Frame>> dartFramesFor(List<Map<String, dynamic>> frames) async {
    var dartFrames = <Frame>[];
    var index = 0;
    for (var frame in frames) {
      var location = frame['location'];
      var functionName = frame['functionName'] as String ?? '';
      functionName = _prettifyMember(functionName.split('.').last);
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
    for (var location in await _locations.locationsForJs(jsLocation.scriptId)) {
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
    // We think we found a location, but for some reason we can't find the script.
    // Just drop the frame.
    // TODO(#700): Understand when this can happen and have a better fix.
    if (script == null) return null;
    return Frame()
      ..code = (CodeRef(id: createId(), name: 'DartCode', kind: CodeKind.kDart))
      ..location = (SourceLocation()
        ..tokenPos = bestLocation.tokenPos
        ..script = script)
      ..kind = FrameKind.kRegular;
  }

  /// Handles pause events coming from the Chrome connection.
  Future<void> _pauseHandler(DebuggerPausedEvent e) async {
    if (inspector == null) return;
    var isolate = inspector.isolate;
    if (isolate == null) return;
    Event event;
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    var params = e.params;
    var jsBreakpointIds = (params['hitBreakpoints'] as List).toSet();
    if (jsBreakpointIds.isNotEmpty) {
      var breakpointIds = jsBreakpointIds
          .map((id) => _breakpoints._byJsId[id])
          // In case the breakpoint was set in Chrome DevTools outside of
          // package:dwds.
          .where((entry) => entry != null)
          .toSet();
      var pauseBreakpoints = isolate.breakpoints
          .where((bp) => breakpointIds.contains(bp.id))
          .toList();
      event = Event(
          kind: EventKind.kPauseBreakpoint,
          timestamp: timestamp,
          isolate: inspector.isolateRef)
        ..pauseBreakpoints = pauseBreakpoints;
    } else if (e.reason == 'exception' || e.reason == 'assert') {
      event = Event(
          kind: EventKind.kPauseException,
          timestamp: timestamp,
          isolate: inspector.isolateRef);
    } else {
      // If we don't have source location continue stepping.
      if (_isStepping && (await _sourceLocation(e)) == null) {
        await _remoteDebugger.sendCommand('Debugger.stepInto');
        return;
      }
      event = Event(
          kind: EventKind.kPauseInterrupted,
          timestamp: timestamp,
          isolate: inspector.isolateRef);
    }
    var jsFrames =
        (e.params['callFrames'] as List).cast<Map<String, dynamic>>();
    try {
      var frames = await dartFramesFor(jsFrames);
      _pausedStack = Stack(frames: frames, messages: []);
      _pausedJsStack = jsFrames;
      if (frames.isNotEmpty) event.topFrame = frames.first;
      isolate.pauseEvent = event;
      _streamNotify('Debug', event);
    } on ChromeDebugException catch (e, s) {
      if (e.exception.description.contains('require is not defined')) {
        logger.warning(
            'Error handling pause event, app does not appear to be loaded',
            e,
            s);
      } else {
        rethrow;
      }
    }
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
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: inspector.isolateRef);
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

  final Map<String, Future<Breakpoint>> _byId = {};

  _Breakpoints(AppInspectorProvider provider) : super(provider);

  /// Adds a breakpoint at [scriptId] and [line] or returns an existing one
  /// if present.
  ///
  /// If a breakpoint does not exists then [ifAbsent] is invoked with an
  /// specified ID for the breakpoint to create. This function must return
  /// a [Breakpoint] with the specified ID.
  ///
  /// We delegate actual breakpoint creation for code simplification purposes,
  /// as we need access to a lot of other objects and add events to streams
  /// etc.
  Future<Breakpoint> add(String scriptId, int line,
      {Future<Breakpoint> Function(String) ifAbsent}) async {
    var id = 'bp/$scriptId#$line';
    var bp = await _byId.putIfAbsent(id, () => ifAbsent(id));
    assert(bp.id == id);
    return bp;
  }

  /// Record the breakpoint.
  ///
  /// Either [dartId] or the Dart breakpoint [bp] must be provided.
  void note({String js, String dartId, Breakpoint bp}) {
    _byJsId[js] = dartId ?? bp?.id;
    _byDartId[dartId ?? bp?.id] = js;
    var isolate = inspector.isolate;
    if (bp != null) {
      isolate?.breakpoints?.add(bp);
    }
  }

  Breakpoint remove({String js, String dartId, Breakpoint bp}) {
    var isolate = inspector.isolate;
    _byJsId.remove(js);
    _byDartId.remove(dartId ?? bp?.id);
    _byId.remove(bp?.id);
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

final escapedPipe = '\$124';
final escapedPound = '\$35';

/// Reformats a JS member name to make it look more Dart-like.
///
/// Logic copied from build/build_web_compilers/web/stack_trace_mapper.dart.
/// TODO(https://github.com/dart-lang/sdk/issues/38869): Remove this logic when
/// DDC stack trace deobfuscation is overhauled.
String _prettifyMember(String member) {
  member = member.replaceAll(escapedPipe, '|');
  return member.contains('|') ? _prettifyExtension(member) : member;
}

/// Reformats a JS member name as an extension method invocation.
String _prettifyExtension(String member) {
  var isSetter = false;
  var pipeIndex = member.indexOf('|');
  var spaceIndex = member.indexOf(' ');
  var poundIndex = member.indexOf(escapedPound);
  if (spaceIndex >= 0) {
    // Here member is a static field or static getter/setter.
    isSetter = member.substring(0, spaceIndex) == 'set';
    member = member.substring(spaceIndex + 1, member.length);
  } else if (poundIndex >= 0) {
    // Here member is a tearoff or local property getter/setter.
    isSetter = member.substring(pipeIndex + 1, poundIndex) == 'set';
    member = member.replaceRange(pipeIndex + 1, poundIndex + 3, '');
  } else {
    var body = member.substring(pipeIndex + 1, member.length);
    if (body.startsWith('unary') || body.startsWith('\$')) {
      // Here member's an operator, so it's safe to unescape everything lazily.
      member = _unescape(member);
    }
  }
  member = member.replaceAll('|', '.');
  return isSetter ? '$member=' : member;
}

/// Unescapes a DDC-escaped JS identifier name.
///
/// Identifier names that contain illegal JS characters are escaped by DDC to a
/// decimal representation of the symbol's UTF-16 value.
/// Warning: this greedily escapes characters, so it can be unsafe in the event
/// that an escaped sequence precedes a number literal in the JS name.
String _unescape(String name) {
  return name.replaceAllMapped(
      RegExp(r'\$[0-9]+'),
      (m) =>
          String.fromCharCode(int.parse(name.substring(m.start + 1, m.end))));
}
