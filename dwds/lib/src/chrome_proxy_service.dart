// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pedantic/pedantic.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger.dart';
import 'helpers.dart';

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  /// Cache of all existing StreamControllers.
  ///
  /// These are all created through [onEvent].
  final _streamControllers = <String, StreamController<Event>>{};

  /// The root `VM` instance. There can only be one of these, but its isolates
  /// are dynamic and roughly map to chrome tabs.
  final VM _vm;

  /// The actual chrome tab running this app.
  final ChromeTab _tab;

  /// The connection with the chrome debug service for the tab.
  final WipConnection tabConnection;

  /// A handler for application assets, e.g. Dart sources.
  final Future<String> Function(String) assetHandler;

  /// The isolate for the current tab.
  ///
  /// This may be null during a hot restart or page refresh.
  Isolate _isolate;

  /// Provides debugger-related functionality.
  Debugger debugger;

  /// Fields that are specific to the current [_isolate].
  ///
  /// These need to get cleared whenever [destroyIsolate] is called.
  final _classes = <String, Class>{};
  final _scriptRefs = <String, ScriptRef>{};
  final _libraries = <String, Library>{};
  final _libraryRefs = <String, LibraryRef>{};
  StreamSubscription<ConsoleAPIEvent> _consoleSubscription;

  ChromeProxyService._(
      this._vm, this._tab, this.tabConnection, this.assetHandler);

  static Future<ChromeProxyService> create(
      ChromeConnection chromeConnection,
      Future<String> Function(String) assetHandler,
      String appInstanceId) async {
    ChromeTab appTab;
    for (var tab in await chromeConnection.getTabs()) {
      if (tab.url.startsWith('chrome-extensions:')) continue;
      var tabConnection = await tab.connect();
      var result = await tabConnection.runtime
          .evaluate(r'window["$dartAppInstanceId"];');
      if (result.value == appInstanceId) {
        appTab = tab;
        break;
      }
      unawaited(tabConnection.close());
    }
    if (appTab == null) {
      throw StateError('Could not connect to application with appInstanceId: '
          '$appInstanceId');
    }
    var tabConnection = await appTab.connect();
    await tabConnection.runtime.enable();

    // TODO: What about `architectureBits`, `targetCPU`, `hostCPU` and `pid`?
    final vm = VM()
      ..isolates = []
      ..name = 'ChromeDebugProxy'
      ..startTime = DateTime.now().millisecondsSinceEpoch
      ..version = Platform.version;
    var service = ChromeProxyService._(vm, appTab, tabConnection, assetHandler);
    await service._initialize();
    await service.createIsolate();
    return service;
  }

  Future<Null> _initialize() async {
    debugger = Debugger(this);
    await debugger.initialize();
  }

  /// Creates a new [_isolate].
  ///
  /// Only one isolate at a time is supported, but they should be cleaned up
  /// with [destroyIsolate] and recreated with this method there is a hot
  /// restart or full page refresh.
  Future<void> createIsolate() async {
    if (_isolate != null) {
      throw UnsupportedError(
          'Cannot create multiple isolates for the same app');
    }

    var id = createId();
    var isolate = Isolate()
      ..id = id
      ..number = id
      ..name = '${_tab.url}:main()'
      ..runnable = true
      ..breakpoints = []
      ..libraries = []
      ..extensionRPCs = [];
    var isolateRef = toIsolateRef(isolate);
    isolate.pauseEvent = Event()
      ..kind = EventKind.kResume
      ..isolate = isolateRef;

    for (var library in await _getLibraryNames()) {
      isolate.libraries.add(LibraryRef()
        ..id = library
        ..name = library
        ..uri = library);
    }

    // TODO: Something more robust here, right now we rely on the 2nd to last
    // library being the root one (the last library is the bootstrap lib).
    isolate.rootLib = isolate.libraries[isolate.libraries.length - 2];

    isolate.extensionRPCs.addAll(await _getExtensionRpcs());

    for (var libraryRef in isolate.libraries) {
      _libraryRefs[libraryRef.id] = libraryRef;
    }

    // Listen for `registerExtension` and `postEvent` calls.
    _setUpChromeConsoleListeners(isolateRef);

    _vm.isolates.add(isolateRef);
    _isolate = isolate;

    streamNotify(
        'Isolate',
        Event()
          ..kind = EventKind.kIsolateStart
          ..isolate = isolateRef);
    streamNotify(
        'Isolate',
        Event()
          ..kind = EventKind.kIsolateRunnable
          ..isolate = isolateRef);

    // TODO: We shouldn't need to fire these events since they exist on the
    // isolate, but devtools doesn't recognize extensions after a page refresh
    // otherwise.
    for (var extensionRpc in isolate.extensionRPCs) {
      streamNotify(
          'Isolate',
          Event()
            ..kind = EventKind.kServiceExtensionAdded
            ..extensionRPC = extensionRpc
            ..isolate = isolateRef);
    }
  }

  /// Should be called when there is a hot restart or full page refresh.
  ///
  /// Clears out [_isolate] and all related cached information.
  void destroyIsolate() {
    if (_isolate == null) return;
    streamNotify(
        'Isolate',
        Event()
          ..kind = EventKind.kIsolateExit
          ..isolate = toIsolateRef(_isolate));
    _vm.isolates.removeWhere((ref) => ref.id == _isolate.id);

    _isolate = null;
    _classes.clear();
    _scriptRefs.clear();
    _libraries.clear();
    _libraryRefs.clear();
    _consoleSubscription.cancel();
    _consoleSubscription = null;
  }

  @override
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    return debugger.addBreakpoint(isolateId, scriptId, line, column: column);
  }

  @override
  Future<Breakpoint> addBreakpointAtEntry(String isolateId, String functionId) {
    throw UnimplementedError();
  }

  @override
  Future<Breakpoint> addBreakpointWithScriptUri(
      String isolateId, String scriptUri, int line,
      {int column}) {
    throw UnimplementedError();
  }

  @override
  Future<Response> callServiceExtension(String method,
      {String isolateId, Map args}) async {
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) _getIsolate(isolateId);
    args ??= <String, String>{};
    var stringArgs = args.map((k, v) => MapEntry(
        k is String ? k : jsonEncode(k), v is String ? v : jsonEncode(v)));
    var expression = '''
require("dart_sdk").developer.invokeExtension(
    "$method", JSON.stringify(${jsonEncode(stringArgs)}));
''';
    var response =
        await tabConnection.runtime.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'awaitPromise': true,
    });
    _handleErrorIfPresent(response, evalContents: expression);
    var decodedResponse =
        jsonDecode(response.result['result']['value'] as String)
            as Map<String, dynamic>;
    if (decodedResponse.containsKey('code') &&
        decodedResponse.containsKey('message') &&
        decodedResponse.containsKey('data')) {
      // ignore: only_throw_errors
      throw RPCError(method, decodedResponse['code'] as int,
          decodedResponse['message'] as String, decodedResponse['data'] as Map);
    } else {
      return Response()..json = decodedResponse;
    }
  }

  @override
  Future<Success> clearCpuProfile(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> clearVMTimeline() {
    throw UnimplementedError();
  }

  @override
  Future<Success> collectAllGarbage(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future evaluate(String isolateId, String targetId, String expression,
      {Map<String, String> scope, bool disableBreakpoints}) async {
    scope ??= {};
    disableBreakpoints ??= false;
    var library = await _getLibrary(isolateId, targetId);
    if (library == null) {
      throw UnsupportedError(
          'Evaluate is only supported when `targetId` is a library.');
    }
    WipResponse result;

    // If there is scope, we use `callFunctionOn` because that accepts the
    // `arguments` option.
    //
    // If there is no scope we run a normal evaluate call.
    if (scope.isEmpty) {
      var evalExpression = '''
(function() {
  ${_getLibrarySnippet(library.uri)};
  return library.$expression;
})();
    ''';
      result = await tabConnection.runtime.sendCommand('Runtime.evaluate',
          params: {'expression': evalExpression});
      _handleErrorIfPresent(result,
          evalContents: evalExpression,
          additionalDetails: {
            'Dart expression': expression,
          });
    } else {
      var argsString = scope.keys.join(', ');
      var arguments = scope.values.map((id) => {'objectId': id}).toList();
      var evalExpression = '''
function($argsString) {
  ${_getLibrarySnippet(library.uri)};
  return library.$expression;
}
    ''';
      result = await tabConnection.runtime
          .sendCommand('Runtime.callFunctionOn', params: {
        'functionDeclaration': evalExpression,
        'arguments': arguments,
        // TODO(jakemac): Use the executionContext instead, or possibly the
        // library object. This will get weird if people try to use `this` in
        // their expression.
        'objectId': scope.values.first,
      });
      _handleErrorIfPresent(result,
          evalContents: evalExpression,
          additionalDetails: {
            'Dart expression': expression,
            'scope': scope,
          });
    }
    var remoteObject =
        RemoteObject(result.result['result'] as Map<String, dynamic>);

    switch (remoteObject.type) {
      case 'string':
        return _primitiveInstance(InstanceKind.kString, remoteObject);
      case 'number':
        return _primitiveInstance(InstanceKind.kDouble, remoteObject);
      case 'boolean':
        return _primitiveInstance(InstanceKind.kBool, remoteObject);
      case 'object':
        return InstanceRef()
          ..kind = InstanceKind.kPlainInstance
          ..id = remoteObject.objectId
          // TODO(jakemac): Create a real ClassRef, we need a way of looking
          // up the library for a given instance to create it though.
          // https://github.com/dart-lang/sdk/issues/36771.
          ..classRef = ClassRef();
      default:
        throw UnsupportedError(
            'Unsupported response type ${remoteObject.type}');
    }
  }

  @override
  Future evaluateInFrame(String isolateId, int frameIndex, String expression,
      {Map<String, String> scope, bool disableBreakpoints}) {
    throw UnimplementedError();
  }

  @override
  Future<AllocationProfile> getAllocationProfile(String isolateId,
      {String gc, bool reset}) {
    throw UnimplementedError();
  }

  @override
  Future<CpuProfile> getCpuProfile(String isolateId, String tags) {
    throw UnimplementedError();
  }

  @override
  Future<FlagList> getFlagList() {
    throw UnimplementedError();
  }

  @override
  Future<ObjRef> getInstances(String isolateId, String classId, int limit) {
    throw UnimplementedError();
  }

  /// Sync version of [getIsolate] for internal use, also has stronger typing
  /// than the public one which has to be dynamic.
  Isolate _getIsolate(String isolateId) {
    if (_isolate?.id == isolateId) return _isolate;
    throw ArgumentError.value(
        isolateId, 'isolateId', 'Unrecognized isolate id');
  }

  @override
  Future getIsolate(String isolateId) async => _getIsolate(isolateId);

  Future<Library> _constructLibrary(LibraryRef libraryRef) async {
    // Fetch information about all the classes in this library.
    var expression = '''
    (function() {
    ${_getLibrarySnippet(libraryRef.uri)}
      var classes = Object.values(library)
        .filter((l) => l && sdkUtils.isType(l));
      return classes.map(function(clazz) {
        var descriptor = {'name': clazz.name};

        // TODO(jakemac): static methods once ddc supports them
        var methods = sdkUtils.getMethods(clazz);
        var methodNames = methods ? Object.keys(methods) : [];
        descriptor['methods'] = {};
        for (var name of methodNames) {
          var method = methods[name];
          descriptor['methods'][name] = {
            // TODO(jakemac): how can we get actual const info?
            "isConst": false,
            "isStatic": false,
          }
        }

        // TODO(jakemac): static fields once ddc supports them
        var fields = sdkUtils.getFields(clazz);
        var fieldNames = fields ? Object.keys(fields) : [];
        descriptor['fields'] = {};
        for (var name of fieldNames) {
          var field = fields[name];
          descriptor['fields'][name] = {
            // TODO(jakemac): how can we get actual const info?
            "isConst": false,
            "isFinal": field.isFinal,
            "isStatic": false,
          }
        }

        return descriptor;
      });
    })()
    ''';
    var classesResult = await tabConnection.runtime.sendCommand(
        'Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    _handleErrorIfPresent(classesResult, evalContents: expression);
    var classDescriptors = (classesResult.result['result']['value'] as List)
        .cast<Map<String, Object>>();
    var classRefs = <ClassRef>[];
    for (var classDescriptor in classDescriptors) {
      var name = classDescriptor['name'] as String;
      var classId = '${libraryRef.id}:$name';
      var classRef = ClassRef()
        ..name = name
        ..id = classId;
      classRefs.add(classRef);

      var methodRefs = <FuncRef>[];
      var methodDescriptors =
          classDescriptor['methods'] as Map<String, dynamic>;
      methodDescriptors.forEach((name, descriptor) {
        var methodId = '$classId:$name';
        methodRefs.add(FuncRef()
          ..id = methodId
          ..name = name
          ..owner = classRef
          ..isConst = descriptor['isConst'] as bool
          ..isStatic = descriptor['isStatic'] as bool);
      });

      var fieldRefs = <FieldRef>[];
      var fieldDescriptors = classDescriptor['fields'] as Map<String, dynamic>;
      fieldDescriptors.forEach((name, descriptor) {
        fieldRefs.add(FieldRef()
          ..name = name
          ..declaredType = InstanceRef()
          ..owner = classRef
          ..isConst = descriptor['isConst'] as bool
          ..isFinal = descriptor['isFinal'] as bool
          ..isStatic = descriptor['isStatic'] as bool);
      });

      // TODO: Implement the rest of these
      // https://github.com/dart-lang/webdev/issues/176.
      _classes[classId] = Class()
        ..classRef = classRef
        ..fields = fieldRefs
        ..functions = methodRefs
        ..id = classId
        ..library = libraryRef
        ..name = name
        ..interfaces = []
        ..subclasses = [];
    }

    // TODO(grouma) - This currently does not support part files.
    // Figure out how to support them.
    var scriptRef = ScriptRef()
      ..uri = libraryRef.uri
      ..id = createId();

    _scriptRefs[scriptRef.id] = scriptRef;

    return Library()
      ..id = libraryRef.id
      ..name = libraryRef.name
      ..uri = libraryRef.uri
      ..classes = classRefs
      ..debuggable = true
      ..dependencies = []
      ..functions = []
      ..scripts = [scriptRef]
      ..variables = [];
  }

  Future<Library> _getLibrary(String isolateId, String objectId) async {
    if (isolateId != _isolate?.id) return null;
    var libraryRef = _libraryRefs[objectId];
    if (libraryRef == null) return null;
    var library = _libraries[objectId];
    if (library != null) return library;
    library = await _constructLibrary(libraryRef);
    _libraries[objectId] = library;
    return library;
  }

  @override
  Future getObject(String isolateId, String objectId,
      {int offset, int count}) async {
    var library = await _getLibrary(isolateId, objectId);
    if (library != null) return library;
    var clazz = _classes[objectId];
    if (clazz != null) return clazz;
    var scriptRef = _scriptRefs[objectId];
    if (scriptRef != null) return await _getScript(isolateId, scriptRef);

    throw UnsupportedError(
        'Only libraries and classes are supported for getObject');
  }

  @override
  Future<ScriptList> getScripts(String isolateId) async {
    var scripts = await scriptRefs(isolateId);
    return ScriptList()..scripts = scripts;
  }

  Future<Script> _getScript(String isolateId, ScriptRef scriptRef) async {
    var libraryId = scriptRef.uri;
    var scriptPath = libraryId.replaceAll('package:', 'packages/');
    var script = await assetHandler(scriptPath);
    return Script()
      ..library = _libraryRefs[libraryId]
      ..id = scriptRef.id
      ..uri = libraryId
      ..tokenPosTable = debugger.tokenPosTableFor(scriptPath)
      ..source = script;
  }

  /// Internal method to list all scripts in the isolate.
  ///
  /// This is used as the underlying mechanism
  /// for [getScripts].
  Future<List<ScriptRef>> scriptRefs(String isolateId) async {
    var isolate = _getIsolate(isolateId);
    var scripts = <ScriptRef>[];
    for (var lib in isolate.libraries) {
      // We can't provide the source for `dart:` imports so ignore for now.
      // Also `main.dart.bootstrap` does not have a corresponding script.
      if (lib.id.startsWith('dart:') || lib.id.endsWith('.bootstrap')) continue;
      scripts.addAll((await _getLibrary(isolateId, lib.id)).scripts);
    }
    // TODO(alanknight): Is this the same as the values in _scriptRefs after
    // constructing all the libraries? Make that clearer.
    return scripts;
  }

  @override
  Future<SourceReport> getSourceReport(String isolateId, List<String> reports,
      {String scriptId, int tokenPos, int endTokenPos, bool forceCompile}) {
    throw UnimplementedError();
  }

  @override
  Future<Stack> getStack(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<VM> getVM() => Future.value(_vm);

  @override
  Future<Response> getVMTimeline() {
    throw UnimplementedError();
  }

  @override
  Future<Version> getVersion() async {
    var version = semver.Version.parse(vmServiceVersion);
    return Version()
      ..major = version.major
      ..minor = version.minor;
  }

  @override
  Future invoke(String isolateId, String targetId, String selector,
      List<String> argumentIds,
      {bool disableBreakpoints}) {
    throw UnimplementedError();
  }

  @override
  Future<Success> kill(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Stream<Event> onEvent(String streamId) {
    return _streamControllers.putIfAbsent(streamId, () {
      switch (streamId) {
        case 'Extension':
        // TODO: right now we only support the `ServiceExtensionAdded` event for
        // the Isolate stream.
        case 'Isolate':
        case 'VM':
        // TODO: https://github.com/dart-lang/webdev/issues/168
        case 'GC':
        // TODO: https://github.com/dart-lang/webdev/issues/168
        case 'Timeline':
        case '_Service':
          return StreamController<Event>.broadcast();
        case 'Debug':
          return _debugStreamController();
        case 'Stdout':
          return _chromeConsoleStreamController(
              (e) => _stdoutTypes.contains(e.type));
        case 'Stderr':
          return _chromeConsoleStreamController(
              (e) => _stderrTypes.contains(e.type),
              includeExceptions: true);
        default:
          throw UnimplementedError('The stream `$streamId` is not supported.');
      }
    }).stream;
  }

  @override
  Future<Success> pause(String isolateId) async {
    var result = await tabConnection.sendCommand('Debugger.pause');
    _handleErrorIfPresent(result);
    return Success();
  }

  @override
  Future<Success> registerService(String service, String alias) async {
    throw UnimplementedError();
  }

  @override
  Future<ReloadReport> reloadSources(String isolateId,
      {bool force, bool pause, String rootLibUri, String packagesUri}) async {
    throw UnimplementedError();
  }

  @override
  Future<Success> removeBreakpoint(String isolateId, String breakpointId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> requestHeapSnapshot(
      String isolateId, String roots, bool collectGarbage) {
    throw UnimplementedError();
  }

  @override
  Future<Success> resume(String isolateId,
      {String step, int frameIndex}) async {
    if (step != null || frameIndex != null) {
      throw ArgumentError('Step and frameIndex are currently unsupported');
    }
    var result = await tabConnection.sendCommand('Debugger.resume');
    _handleErrorIfPresent(result);
    return Success();
  }

  @override
  Future<Success> setExceptionPauseMode(String isolateId, String mode) async {
    // Validates that the ID is correct.
    _getIsolate(isolateId);

    var pauseState = _pauseModePauseStates[mode.toLowerCase()] ??
        // ignore: only_throw_errors
        (throw RPCError(
            'setExceptionPauseMode', -32602, 'Unsupported mode `$mode`'));
    await tabConnection.debugger.setPauseOnExceptions(pauseState);
    return Success();
  }

  @override
  Future<Success> setFlag(String name, String value) {
    throw UnimplementedError();
  }

  @override
  Future<Success> setLibraryDebuggable(
      String isolateId, String libraryId, bool isDebuggable) {
    throw UnimplementedError();
  }

  @override
  Future<Success> setName(String isolateId, String name) async {
    var isolate = _getIsolate(isolateId);
    isolate.name = name;
    return Success();
  }

  @override
  Future<Success> setVMName(String name) async {
    _vm.name = name;
    streamNotify(
        'VM',
        Event()
          ..kind = EventKind.kVMUpdate
          ..vm = toVMRef(_vm));
    return Success();
  }

  @override
  Future<Success> setVMTimelineFlags(List<String> recordedStreams) {
    throw UnimplementedError();
  }

  @override
  Future<Success> streamCancel(String streamId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> streamListen(String streamId) async {
    onEvent(streamId);
    return Success();
  }

  /// Returns a streamController that listens for console logs from chrome and
  /// adds all events passing [filter] to the stream.
  StreamController<Event> _chromeConsoleStreamController(
      bool Function(ConsoleAPIEvent) filter,
      {bool includeExceptions = false}) {
    StreamController<Event> controller;
    StreamSubscription chromeConsoleSubscription;
    StreamSubscription exceptionsSubscription;
    // This is an edge case for this lint apparently
    //
    // ignore: join_return_with_assignment
    controller = StreamController<Event>.broadcast(onCancel: () {
      chromeConsoleSubscription?.cancel();
      exceptionsSubscription?.cancel();
    }, onListen: () {
      chromeConsoleSubscription =
          tabConnection.runtime.onConsoleAPICalled.listen((e) {
        if (_isolate == null) return;
        if (!filter(e)) return;
        var args = e.params['args'] as List;
        var item = args[0] as Map;
        var value = '${item["value"]}\n';
        controller.add(Event()
          ..kind = EventKind.kWriteEvent
          ..isolate = toIsolateRef(_isolate)
          ..bytes = base64.encode(utf8.encode(value))
          ..timestamp = e.timestamp.toInt());
      });
      if (includeExceptions) {
        exceptionsSubscription =
            tabConnection.runtime.onExceptionThrown.listen((e) {
          if (_isolate == null) return;
          controller.add(Event()
            ..kind = EventKind.kWriteEvent
            ..isolate = toIsolateRef(_isolate)
            ..bytes = base64
                .encode(utf8.encode(e.exceptionDetails.exception.description)));
        });
      }
    });
    return controller;
  }

  /// Listens to the `debugger` events from chrome and translates those to
  /// the `Debug` stream events for the vm service protocol.
  ///
  // TODO: Implement the rest https://github.com/dart-lang/webdev/issues/166
  StreamController<Event> _debugStreamController() {
    StreamSubscription pauseSubscription;
    StreamSubscription resumeSubscription;
    return StreamController<Event>.broadcast(onListen: () {
      pauseSubscription = tabConnection.debugger.onPaused.listen((e) {
        if (_isolate == null) return;
        var event = Event()..isolate = toIsolateRef(_isolate);
        var params = e.params;
        var breakpoints = params['hitBreakpoints'] as List;
        if (breakpoints.isNotEmpty) {
          // TODO: Set `breakpoint` and `pauseBreakpoints` fields.
          event.kind = EventKind.kPauseBreakpoint;
        } else if (e.reason == 'exception' || e.reason == 'assert') {
          event.kind = EventKind.kPauseException;
        } else {
          event.kind = EventKind.kPauseInterrupted;
        }
        streamNotify('Debug', event);
      });
      resumeSubscription = tabConnection.debugger.onResumed.listen((e) {
        if (_isolate == null) return;
        streamNotify(
            'Debug',
            Event()
              ..kind = EventKind.kResume
              ..isolate = toIsolateRef(_isolate));
      });
    }, onCancel: () {
      pauseSubscription.cancel();
      resumeSubscription.cancel();
    });
  }

  /// Runs an eval on the page to compute all existing registered extensions.
  Future<List<String>> _getExtensionRpcs() async {
    var expression = "require('dart_sdk').developer._extensions.keys.toList();";
    var extensionsResult = await tabConnection.runtime.sendCommand(
        'Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    _handleErrorIfPresent(extensionsResult, evalContents: expression);
    return List.from(extensionsResult.result['result']['value'] as List);
  }

  /// Runs an eval on the page to compute all the library names in the app.
  Future<List<String>> _getLibraryNames() async {
    var expression = "require('dart_sdk').dart.getLibraries();";
    var librariesResult = await tabConnection.runtime.sendCommand(
        'Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    _handleErrorIfPresent(librariesResult, evalContents: expression);
    return List.from(librariesResult.result['result']['value'] as List);
  }

  /// Listens for chrome console events and handles the ones we care about.
  void _setUpChromeConsoleListeners(IsolateRef isolateRef) {
    _consoleSubscription = tabConnection.runtime.onConsoleAPICalled
        .listen((ConsoleAPIEvent event) {
      if (_isolate == null) return;
      if (event.type != 'debug') return;
      var firstArgValue = event.args[0].value as String;
      switch (firstArgValue) {
        case 'dart.developer.registerExtension':
          var service = event.args[1].value as String;
          _isolate.extensionRPCs.add(service);
          streamNotify(
              'Isolate',
              Event()
                ..kind = EventKind.kServiceExtensionAdded
                ..extensionRPC = service
                ..isolate = isolateRef);
          break;
        case 'dart.developer.postEvent':
          streamNotify(
              'Extension',
              Event()
                ..kind = EventKind.kExtension
                ..extensionKind = event.args[1].value as String
                ..extensionData = ExtensionData.parse(
                    jsonDecode(event.args[2].value as String) as Map)
                ..isolate = isolateRef);
          break;
        case 'dart.developer.inspect':
          // All inspected objects should be real objects.
          if (event.args[1].type != 'object') break;

          var inspectee = InstanceRef()
            ..kind = InstanceKind.kPlainInstance
            ..id = event.args[1].objectId
            // TODO(jakemac): Create a real ClassRef, we need a way of looking
            // up the library for a given instance to create it though.
            // https://github.com/dart-lang/sdk/issues/36771.
            ..classRef = ClassRef();
          streamNotify(
              'Debug',
              Event()
                ..kind = EventKind.kInspect
                ..inspectee = inspectee
                ..timestamp = event.timestamp.toInt()
                ..isolate = isolateRef);
          break;
        default:
          break;
      }
    });
  }

  /// Adds [event] to the stream with [streamId] if there is anybody listening
  /// on that stream.
  void streamNotify(String streamId, Event event) {
    var controller = _streamControllers[streamId];
    if (controller == null) return;
    controller.add(event);
  }
}

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stderr` logs.
const _stderrTypes = ['error'];

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stdout` logs.
const _stdoutTypes = ['log', 'info', 'warning'];

/// Throws an [ExceptionDetails] object if `exceptionDetails` is present on the
/// result.
void _handleErrorIfPresent(WipResponse response,
    {String evalContents, Object additionalDetails}) {
  if (response.result.containsKey('exceptionDetails')) {
    throw ChromeDebugException(
        response.result['exceptionDetails'] as Map<String, dynamic>,
        evalContents: evalContents,
        additionalDetails: additionalDetails);
  }
}

/// Creates a snippet of JS code that initializes a `library` variable that has
/// the actual library object in DDC for [libraryUri].
String _getLibrarySnippet(String libraryUri) => '''
  var libraryName = '$libraryUri';
  var sdkUtils = require('dart_sdk').dart;
  var moduleName = sdkUtils.getModuleNames().find(
    (name) => sdkUtils.getModuleLibraries(name)[libraryName]);
  // need to strip out the trailing `.ddc`.
  var module = require(moduleName.replace('.ddc', ''));
  // Strip the 'package:<package_name>` name out of the library name, if this
  // library is from a package.
  var startIndex = libraryName.startsWith('package:')
      ? libraryName.indexOf("/") + 1 : 0;
  var libraryIdentifier = libraryName
    .substring(
      startIndex,
      libraryName.length - ".dart".length)
    .replace(/\\//gi, "__");
  var library = module[libraryIdentifier];
''';

class ChromeDebugException extends ExceptionDetails implements Exception {
  /// Optional, additional information about the exception.
  final Object additionalDetails;

  /// Optional, the exact contents of the eval that was attempted.
  final String evalContents;

  ChromeDebugException(Map<String, dynamic> exceptionDetails,
      {this.additionalDetails, this.evalContents})
      : super(exceptionDetails);

  @override
  String toString() {
    var description = StringBuffer()
      ..writeln('Unexpected error from chrome devtools:');
    if (text != null) {
      description.writeln('text: $text');
    }
    if (exception != null) {
      description.writeln('exception:');
      description.writeln('  description: ${exception.description}');
      description.writeln('  type: ${exception.type}');
      description.writeln('  value: ${exception.value}');
    }
    if (evalContents != null) {
      description.writeln('attempted JS eval: `$evalContents`');
    }
    if (additionalDetails != null) {
      description.writeln('additional details:\n  $additionalDetails');
    }
    return description.toString();
  }
}

/// Converts from ExceptionPauseMode strings to [PauseState] enums.
const _pauseModePauseStates = {
  'none': PauseState.none,
  'all': PauseState.all,
  'unhandled': PauseState.uncaught,
};

/// Creates an [InstanceRef] for a primitive [RemoteObject].
InstanceRef _primitiveInstance(String kind, RemoteObject remoteObject) {
  var classRef = ClassRef()
    ..id = 'dart:core:${remoteObject.type}'
    ..name = kind;
  return InstanceRef()
    ..valueAsString = '${remoteObject.value}'
    ..classRef = classRef
    ..kind = kind;
}
