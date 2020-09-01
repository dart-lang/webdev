// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart'
    hide StackTrace;

import '../loaders/strategy.dart';
import '../readers/asset_reader.dart';
import '../services/chrome_proxy_service.dart';
import '../utilities/conversions.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/objects.dart' show Property;
import '../utilities/shared.dart';
import 'dart_scope.dart';
import 'frame_computer.dart';
import 'location.dart';
import 'remote_debugger.dart';

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

  final StreamNotify _streamNotify;
  final AssetReader _assetReader;
  final Locations _locations;
  final String _root;

  Debugger._(
    this._remoteDebugger,
    this._streamNotify,
    AppInspectorProvider provider,
    this._assetReader,
    this._locations,
    this._root,
  )   : _breakpoints = _Breakpoints(
            locations: _locations,
            provider: provider,
            remoteDebugger: _remoteDebugger,
            root: _root),
        super(provider);

  /// The breakpoints we have set so far, indexable by either
  /// Dart or JS ID.
  final _Breakpoints _breakpoints;

  PauseState _pauseState = PauseState.none;

  String get pauseState => _pauseModePauseStates.entries
      .firstWhere((entry) => entry.value == _pauseState)
      .key;

  /// The JS frames at the current paused location.
  ///
  /// The most important thing here is that frames are identified by
  /// frameIndex in the Dart API, but by frame Id in Chrome, so we need
  /// to keep the JS frames and their Ids around.
  FrameComputer stackComputer;

  bool _isStepping = false;

  Future<Success> pause() async {
    _isStepping = false;
    var result = await _remoteDebugger.pause();
    handleErrorIfPresent(result);
    return Success();
  }

  Future<Success> setExceptionPauseMode(String isolateId, String mode) async {
    checkIsolate('setExceptionPauseMode', isolateId);
    mode = mode?.toLowerCase();
    if (!_pauseModePauseStates.containsKey(mode)) {
      throwInvalidParam('setExceptionPauseMode', 'Unsupported mode: $mode');
    }
    _pauseState = _pauseModePauseStates[mode];
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
    checkIsolate('resume', isolateId);
    if (frameIndex != null) {
      throw ArgumentError('FrameIndex is currently unsupported.');
    }
    WipResponse result;
    if (step != null) {
      _isStepping = true;
      switch (step) {
        case 'Over':
          result = await _remoteDebugger.stepOver();
          break;
        case 'Out':
          result = await _remoteDebugger.stepOut();
          break;
        case 'Into':
          result = await _remoteDebugger.stepInto();
          break;
        default:
          throwInvalidParam('resume', 'Unexpected value for step: $step');
      }
    } else {
      _isStepping = false;
      result = await _remoteDebugger.resume();
    }
    handleErrorIfPresent(result);
    return Success();
  }

  /// Returns the current Dart stack for the paused debugger.
  ///
  /// Returns null if the debugger is not paused.
  Future<Stack> getStack(String isolateId) async {
    checkIsolate('getStack', isolateId);
    if (stackComputer == null) return null;

    var frames = await stackComputer.calculateFrames();
    return Stack(frames: frames, messages: []);
  }

  static Future<Debugger> create(
    RemoteDebugger remoteDebugger,
    StreamNotify streamNotify,
    AppInspectorProvider appInspectorProvider,
    AssetReader assetReader,
    Locations locations,
    String root,
  ) async {
    var debugger = Debugger._(
      remoteDebugger,
      streamNotify,
      appInspectorProvider,
      assetReader,
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
      });
      _remoteDebugger?.onPaused?.listen(_pauseHandler);
      _remoteDebugger?.onResumed?.listen(_resumeHandler);
    }, onError: (e, StackTrace s) {
      logger.warning('Error handling Chrome event', e, s);
    });

    handleErrorIfPresent(await _remoteDebugger?.enablePage());
    handleErrorIfPresent(await _remoteDebugger?.enable() as WipResponse);

    // Enable collecting information about async frames when paused.
    handleErrorIfPresent(await _remoteDebugger
        ?.sendCommand('Debugger.setAsyncCallStackDepth', params: {
      'maxDepth': 128,
    }));
  }

  /// Black boxes the Dart SDK and paths in [_pathsToBlackBox].
  Future<void> _blackBoxIfNecessary(WipScript script) async {
    // Ignore query parameters.
    var url = script.url?.split('?')?.first ?? '';
    if (url.endsWith('dart_sdk.js') || url.endsWith('dart_sdk.ddk.js')) {
      await _blackBoxSdk(script);
    } else if (_pathsToBlackBox.any(url.contains)) {
      var content =
          await _assetReader.dartSourceContents(DartUri(url).serverPath);
      if (content == null) return;
      var lines = content.split('\n');
      await _blackBoxRanges(script.scriptId, [lines.length]);
    }
  }

  /// Black boxes the SDK excluding the range which includes exception logic.
  Future<void> _blackBoxSdk(WipScript script) async {
    var content =
        await _assetReader.dartSourceContents(DartUri(script.url).serverPath);
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
    stackComputer = FrameComputer(this, []);
  }

  /// Add a breakpoint at the given position.
  ///
  /// Note that line and column are Dart source locations and are one-based.
  Future<Breakpoint> addBreakpoint(
    String isolateId,
    String scriptId,
    int line, {
    int column,
  }) async {
    checkIsolate('addBreakpoint', isolateId);
    final breakpoint = await _breakpoints.add(scriptId, line);
    _notifyBreakpoint(breakpoint);
    return breakpoint;
  }

  Future<ScriptRef> _updatedScriptRefFor(Breakpoint breakpoint) async {
    var oldRef = (breakpoint.location as SourceLocation).script;
    var dartUri = DartUri(oldRef.uri, _root);
    return await inspector.scriptRefFor(dartUri.serverPath);
  }

  Future<void> reestablishBreakpoints(
    Set<Breakpoint> previousBreakpoints,
    Set<Breakpoint> disabledBreakpoints,
  ) async {
    // Previous breakpoints were never removed from Chrome since we use
    // `setBreakpointByUrl`. We simply need to update the references.
    for (var breakpoint in previousBreakpoints) {
      var scriptRef = await _updatedScriptRefFor(breakpoint);
      var updatedLocation = await _locations.locationForDart(
          DartUri(scriptRef.uri, _root), _lineNumberFor(breakpoint));
      var updatedBreakpoint = _breakpoints._dartBreakpoint(
          scriptRef, updatedLocation, breakpoint.id);
      _breakpoints._note(
          bp: updatedBreakpoint,
          jsId: _breakpoints._jsIdByDartId[updatedBreakpoint.id]);
      _notifyBreakpoint(updatedBreakpoint);
    }
    // Disabled breakpoints were actually removed from Chrome so simply add
    // them back.
    for (var breakpoint in disabledBreakpoints) {
      await addBreakpoint(
          inspector.isolate.id,
          (await _updatedScriptRefFor(breakpoint)).id,
          _lineNumberFor(breakpoint));
    }
  }

  void _notifyBreakpoint(Breakpoint breakpoint) {
    final event = Event(
      kind: EventKind.kBreakpointAdded,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isolate: inspector.isolateRef,
    );
    event.breakpoint = breakpoint;
    _streamNotify('Debug', event);
  }

  /// Remove a Dart breakpoint.
  Future<Success> removeBreakpoint(
      String isolateId, String breakpointId) async {
    checkIsolate('removeBreakpoint', isolateId);
    if (breakpointId == null) {
      throwInvalidParam('removeBreakpoint', 'breakpointId not provided');
    }

    final jsId = _breakpoints.jsId(breakpointId);
    await _removeBreakpoint(jsId);

    var bp = _breakpoints.remove(jsId: jsId, dartId: breakpointId);
    if (bp != null) {
      _streamNotify(
        'Debug',
        Event(
            kind: EventKind.kBreakpointRemoved,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isolate: inspector.isolateRef)
          ..breakpoint = bp,
      );
    }

    return Success();
  }

  /// Call the Chrome protocol removeBreakpoint.
  Future<void> _removeBreakpoint(String breakpointId) async {
    try {
      var response = await _remoteDebugger.removeBreakpoint(breakpointId);
      handleErrorIfPresent(response);
    } on WipError catch (e) {
      throw RPCError('removeBreakpoint', 102, '$e');
    }
  }

  /// Returns source [Location] for the paused event.
  ///
  /// If we do not have [Location] data for the embedded JS location, null is
  /// returned.
  Future<Location> _sourceLocation(DebuggerPausedEvent e) {
    var frame = e.params['callFrames'][0];
    var location = frame['location'];
    return _locations.locationForJs(
        frame['url'] as String, (location['lineNumber'] as int) + 1);
  }

  /// The variables visible in a frame in Dart protocol [BoundVariable] form.
  Future<List<BoundVariable>> variablesFor(WipCallFrame frame) async {
    // TODO(alanknight): Can these be moved to dart_scope.dart?
    var properties = await visibleProperties(debugger: this, frame: frame);
    var boundVariables = await Future.wait(
      properties.map((property) async => await _boundVariable(property)),
    );

    // Filter out variables that do not come from dart code, such as native
    // JavaScript objects
    return boundVariables
        .where((bv) =>
            bv != null &&
            !_isNativeJsObject(bv.value as vm_service.InstanceRef))
        .toList();
  }

  bool _isNativeJsObject(vm_service.InstanceRef instanceRef) =>
      instanceRef?.classRef?.name == 'NativeJavaScriptObject';

  Future<BoundVariable> _boundVariable(Property property) async {
    // We return one level of properties from this object. Sub-properties are
    // another round trip.
    var instanceRef =
        await inspector.instanceHelper.instanceRefFor(property.value);
    // Skip null instance refs, which we get for weird objects, e.g.
    // properties that are getter/setter pairs.
    // TODO(alanknight): Handle these properly.
    if (instanceRef == null) return null;

    return BoundVariable(
      name: property.name,
      value: instanceRef,
      // TODO(grouma) - Provide actual token positions.
      declarationTokenPos: -1,
      scopeStartTokenPos: -1,
      scopeEndTokenPos: -1,
    );
  }

  /// Find a sub-range of the entries for a Map/List when offset and/or count
  /// have been specified on a getObject request.
  ///
  /// If the object referenced by [id] is not a system List or Map then this
  /// will just return a RemoteObject for it and ignore [offset], [count] and
  /// [length]. If it is, then [length] should be the number of entries in the
  /// List/Map and [offset] and [count] should indicate the desired range.
  Future<RemoteObject> _subrange(
      String id, int offset, int count, int length) async {
    // TODO(#809): Sometimes we already know the type of the object, and
    // we could take advantage of that to short-circuit.
    var receiver = remoteObjectFor(id);
    var end = count == null ? null : math.min(offset + count, length);
    var actualCount = count ?? length - offset;
    var args =
        [offset, actualCount, end].map(dartIdFor).map(remoteObjectFor).toList();
    // If this is a List, just call sublist. If it's a Map, get the entries, but
    // avoid doing a toList on a large map using skip/take to get the section we
    // want. To make those alternatives easier in JS, pass both count and end.
    var expression = '''
        function (offset, count, end) {
          const sdk = ${globalLoadStrategy.loadModuleSnippet}("dart_sdk");
          if (sdk.core.Map.is(this)) {
            const entries = sdk.dart.dload(this, "entries");
            const skipped = sdk.dart.dsend(entries, "skip", [offset])
            const taken = sdk.dart.dsend(skipped, "take", [count]);
            return sdk.dart.dsend(taken, "toList", []);
          } else  if (sdk.core.List.is(this)) {
            return sdk.dart.dsendRepl(this, "sublist", [offset, end]);
          } else {
            return this;
          }
        }
        ''';
    return await inspector.jsCallFunctionOn(receiver, expression, args);
  }

  /// Calls the Chrome Runtime.getProperties API for the object with [objectId].
  ///
  /// Note that the property names are JS names, e.g.
  /// Symbol(DartClass.actualName) and will need to be converted. For a system
  /// List or Map, [offset] and/or [count] can be provided to indicate a desired
  /// range of entries. If those are provided, then [length] should also be
  /// provided to indicate the total length of the List/Map.
  Future<List<Property>> getProperties(String objectId,
      {int offset, int count, int length}) async {
    var rangeId = objectId;
    if (offset != null || count != null) {
      var range = await _subrange(objectId, offset ?? 0, count, length);
      rangeId = range.objectId;
    }
    var response =
        await _remoteDebugger.sendCommand('Runtime.getProperties', params: {
      'objectId': rangeId,
      'ownProperties': true,
    });
    var jsProperties = response.result['result'];
    var properties = (jsProperties as List)
        .map<Property>((each) => Property(each as Map<String, dynamic>))
        .toList();
    return properties;
  }

  /// Returns a Dart [Frame] for a JS [frame].
  Future<Frame> calculateDartFrameFor(
    WipCallFrame frame,
    int frameIndex, {
    bool populateVariables = true,
  }) async {
    var location = frame.location;
    // Chrome is 0 based. Account for this.
    var line = location.lineNumber + 1;
    var column = location.columnNumber + 1;
    // TODO(sdk/issues/37240) - ideally we look for an exact location instead
    // of the closest location on a given line.
    Location bestLocation;
    for (var location in await _locations.locationsForUrl(frame.url)) {
      if (location.jsLocation.line == line) {
        bestLocation ??= location;
        if ((location.jsLocation.column - column).abs() <
            (bestLocation.jsLocation.column - column).abs()) {
          bestLocation = location;
        }
      }
    }
    if (bestLocation == null) return null;

    var script =
        await inspector?.scriptRefFor(bestLocation.dartLocation.uri.serverPath);
    // We think we found a location, but for some reason we can't find the
    // script. Just drop the frame.
    // TODO(#700): Understand when this can happen and have a better fix.
    if (script == null) return null;

    var functionName =
        _prettifyMember((frame.functionName ?? '').split('.').last);
    var codeRefName = functionName.isEmpty ? '<closure>' : functionName;

    var dartFrame = Frame(
      index: frameIndex,
      code: CodeRef(
        name: codeRefName,
        kind: CodeKind.kDart,
        id: createId(),
      ),
      location: SourceLocation(tokenPos: bestLocation.tokenPos, script: script),
      kind: FrameKind.kRegular,
    );

    // Don't populate variables for async frames.
    if (populateVariables) {
      dartFrame.vars = await variablesFor(frame);
    }

    return dartFrame;
  }

  /// Handles pause events coming from the Chrome connection.
  Future<void> _pauseHandler(DebuggerPausedEvent e) async {
    if (inspector == null) return;

    var isolate = inspector.isolate;
    if (isolate == null) return;

    Event event;
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    var jsBreakpointIds = e.hitBreakpoints ?? [];
    if (jsBreakpointIds.isNotEmpty) {
      var breakpointIds = jsBreakpointIds
          .map((id) => _breakpoints._dartIdByJsId[id])
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
      InstanceRef exception;

      if (e.data is Map<String, dynamic>) {
        var map = e.data as Map<String, dynamic>;
        if (map['type'] == 'object') {
          // The className here is generally 'DartError'.
          var obj = RemoteObject(map);
          exception = await inspector.instanceHelper.instanceRefFor(obj);

          // TODO: The exception object generally doesn't get converted to a
          // Dart object (and instead has a classRef name of 'NativeJavaScriptObject').
          if (_isNativeJsObject(exception)) {
            if (obj.description != null) {
              // Create a string exception object.
              exception = await inspector.instanceHelper
                  .instanceRefFor(obj.description);
            } else {
              exception = null;
            }
          }
        }
      }

      event = Event(
        kind: EventKind.kPauseException,
        timestamp: timestamp,
        isolate: inspector.isolateRef,
        exception: exception,
      );
    } else {
      // If we don't have source location continue stepping.
      if (_isStepping && (await _sourceLocation(e)) == null) {
        await _remoteDebugger.stepInto();
        return;
      }
      event = Event(
          kind: EventKind.kPauseInterrupted,
          timestamp: timestamp,
          isolate: inspector.isolateRef);
    }

    // Calculate the frames (and handle any exceptions that may occur).
    stackComputer = FrameComputer(
      this,
      e.getCallFrames().toList(),
      asyncFrames: e.asyncStackTrace,
    );

    try {
      event.topFrame = await stackComputer.calculateTopFrame();
    } catch (e, s) {
      // TODO: Return information about the error to the user.
      logger.warning('Error calculating Dart frames', e, s);
    }

    isolate.pauseEvent = event;
    _streamNotify('Debug', event);
  }

  /// Handles resume events coming from the Chrome connection.
  Future<void> _resumeHandler(DebuggerResumedEvent _) async {
    // We can receive a resume event in the middle of a reload which will result
    // in a null isolate.
    var isolate = inspector?.isolate;
    if (isolate == null) return;

    stackComputer = null;
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
    if (stackComputer == null) {
      throw RPCError('evaluateInFrame', 106,
          'Cannot evaluate on a call frame when the program is not paused');
    }
    return evaluateJsOnCallFrame(
        stackComputer.jsFrameForIndex(frameIndex).callFrameId, expression);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluateOnCallFrame on
  /// the call frame with id [callFrameId].
  Future<RemoteObject> evaluateJsOnCallFrame(
      String callFrameId, String expression) async {
    // TODO(alanknight): Support a version with arguments if needed.
    try {
      return await _remoteDebugger.evaluateOnCallFrame(callFrameId, expression);
    } on ExceptionDetails catch (e) {
      throw ChromeDebugException(
        e.json,
        evalContents: expression,
        additionalDetails: {
          'Dart expression': expression,
        },
      );
    }
  }
}

/// Returns the Dart line number for the provided breakpoint.
int _lineNumberFor(Breakpoint breakpoint) =>
    int.parse(breakpoint.id.split('#').last);

/// Returns the breakpoint ID for the provided Dart script ID and Dart line
/// number.
String breakpointIdFor(String scriptId, int line) => 'bp/$scriptId#$line';

/// Keeps track of the Dart and JS breakpoint Ids that correspond.
class _Breakpoints extends Domain {
  final Map<String, String> _dartIdByJsId = {};
  final Map<String, String> _jsIdByDartId = {};

  final Map<String, Breakpoint> _bpByDartId = {};

  final Locations locations;
  final RemoteDebugger remoteDebugger;

  /// The root URI from which the application is served.
  final String root;

  _Breakpoints({
    @required this.locations,
    @required AppInspectorProvider provider,
    @required this.remoteDebugger,
    @required this.root,
  }) : super(provider);

  /// Adds a breakpoint at [scriptId] and [line] or returns an existing one if
  /// present.
  Future<Breakpoint> add(String scriptId, int line) async {
    final id = breakpointIdFor(scriptId, line);
    if (_bpByDartId.containsKey(id)) {
      throw RPCError('addBreakpoint', 102, 'Breakpoint already exists.');
    }

    var dartScript = inspector.scriptWithId(scriptId);
    var dartUri = DartUri(dartScript.uri, root);
    var location = await locations.locationForDart(dartUri, line);
    // TODO: Handle cases where a breakpoint can't be set exactly at that line.
    if (location == null) {
      throw RPCError(
          'addBreakpoint',
          102,
          'The VM is unable to add a breakpoint '
              'at the specified line or function');
    }

    try {
      var dartBreakpoint = _dartBreakpoint(dartScript, location, id);
      var jsBreakpointId = await _setJsBreakpoint(location);
      _bpByDartId[id] = dartBreakpoint;
      _note(jsId: jsBreakpointId, bp: dartBreakpoint);
      return dartBreakpoint;
    } on WipError catch (wipError) {
      throw RPCError('addBreakpoint', 102, '$wipError');
    }
  }

  /// Create a Dart breakpoint at [location] in [dartScript] with [id].
  Breakpoint _dartBreakpoint(
      ScriptRef dartScript, Location location, String id) {
    var breakpoint = Breakpoint(
        id: id,
        breakpointNumber: int.parse(createId()),
        resolved: true,
        location:
            SourceLocation(script: dartScript, tokenPos: location.tokenPos))
      ..id = id;
    return breakpoint;
  }

  /// Calls the Chrome protocol setBreakpoint and returns the remote ID.
  Future<String> _setJsBreakpoint(Location location) async {
    // Location is 0 based according to:
    // https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Location

    // The module can be loaded from a nested path and contain an ETAG suffix.
    var urlRegex = '.*${location.jsLocation.module}.*';
    var response = await remoteDebugger
        .sendCommand('Debugger.setBreakpointByUrl', params: {
      'urlRegex': urlRegex,
      'lineNumber': location.jsLocation.line - 1,
    });
    return response.result['breakpointId'] as String;
  }

  /// Records the internal Dart <=> JS breakpoint id mapping and adds the
  /// breakpoint to the current isolates list of breakpoints.
  void _note({@required Breakpoint bp, @required String jsId}) {
    _dartIdByJsId[jsId] = bp.id;
    _jsIdByDartId[bp.id] = jsId;
    var isolate = inspector.isolate;
    isolate?.breakpoints?.add(bp);
  }

  Breakpoint remove({
    @required String jsId,
    @required String dartId,
  }) {
    var isolate = inspector.isolate;
    _dartIdByJsId.remove(jsId);
    _jsIdByDartId.remove(dartId);
    isolate?.breakpoints?.removeWhere((b) => b.id == dartId);
    return _bpByDartId.remove(dartId);
  }

  String jsId(String dartId) => _jsIdByDartId[dartId];
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
  if (member.contains('|')) {
    return _prettifyExtension(member);
  } else {
    if (member.startsWith('[') && member.endsWith(']')) {
      member = member.substring(1, member.length - 1);
    }
    return member;
  }
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
