// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'helpers.dart';

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  /// The isolate for the current tab.
  final Isolate _isolate;

  /// Cache of all existing StreamControllers.
  ///
  /// These are all created through [onEvent].
  final _streamControllers = <String, StreamController<Event>>{};

  /// The root `VM` instance. There can only be one of these, but its isolates
  /// are dynamic and roughly map to chrome tabs.
  final VM _vm;

  /// The connection with the chrome debug service for the tab.
  final WipConnection _tabConnection;

  /// A handler for application assets, e.g. Dart sources.
  final Future<String> Function(String) _assetHandler;

  final _classes = <String, Class>{};
  final _libraries = <String, Future<Library>>{};
  final _scriptRefs = <String, ScriptRef>{};

  ChromeProxyService._(
      this._vm, this._isolate, this._tabConnection, this._assetHandler) {
    // Listen for `registerExtension` and `postEvent` calls.
    _tabConnection.runtime.onConsoleAPICalled.listen((ConsoleAPIEvent event) {
      if (event.type != 'debug') return;
      var firstArgValue = event.args[0].value as String;
      switch (firstArgValue) {
        case 'dart.developer.registerExtension':
          var service = event.args[1].value as String;
          _isolate.extensionRPCs.add(service);
          _streamNotify(
              'Isolate',
              Event()
                ..kind = EventKind.kServiceExtensionAdded
                ..extensionRPC = service);
          break;
        case 'dart.developer.postEvent':
          _streamNotify(
              'Extension',
              Event()
                ..kind = EventKind.kExtension
                ..extensionKind = event.args[1].value as String
                ..extensionData = ExtensionData.parse(
                    jsonDecode(event.args[2].value as String) as Map));
          break;
        case 'dart.developer.inspect':
          // All inspected objects should be real objects.
          if (event.args[1].type != 'object') break;

          var inspectee = InstanceRef()
            ..kind = InstanceKind.kPlainInstance
            ..id = event.args[1].objectId
            // TODO: A real classref? we need something here so it can properly
            // serialize, but it isn't used by the widget inspector.
            ..classRef = ClassRef();
          _streamNotify(
              'Debug',
              Event()
                ..kind = EventKind.kInspect
                ..inspectee = inspectee
                ..timestamp = event.timestamp.toInt());
          break;
        default:
          break;
      }
    });
  }

  static Future<ChromeProxyService> create(ChromeConnection chromeConnection,
      Future<String> Function(String) assetHandler, String tabUrl) async {
    var tab = await chromeConnection.getTab((tab) => tab.url == tabUrl);
    var id = createId();
    var isolate = Isolate()
      ..id = id
      ..number = id
      ..name = '${tab.url}:main()'
      ..runnable = true
      ..breakpoints = []
      ..libraries = []
      ..extensionRPCs = [];
    var isolateRef = toIsolateRef(isolate);
    isolate.pauseEvent = Event()
      ..kind = EventKind.kResume
      ..isolate = isolateRef;
    var tabConnection = await tab.connect();
    await tabConnection.debugger.enable();
    await tabConnection.runtime.enable();

    // Query for the available libraries and add them to the isolate
    var librariesResult = await tabConnection.runtime
        .sendCommand('Runtime.evaluate', params: {
      'expression': "require('dart_sdk').dart.getLibraries();",
      'returnByValue': true
    });
    _handleErrorIfPresent(librariesResult);
    var libraryNames =
        (librariesResult.result['result']['value'] as List).cast<String>();
    for (var library in libraryNames) {
      isolate.libraries.add(LibraryRef()
        ..id = library
        ..name = library
        ..uri = library);
    }
    // TODO: Something more robust here, right now we rely on the 2nd to last
    // library being the root one (the last library is the bootstrap lib).
    isolate.rootLib = isolate.libraries[isolate.libraries.length - 2];

    // Find all the previously registered extensions on the page and add them
    // to `extensionRPCs`.
    var extensionsResult =
        await tabConnection.runtime.sendCommand('Runtime.evaluate', params: {
      'expression': "require('dart_sdk').developer._extensions.keys.toList();",
      'returnByValue': true
    });
    _handleErrorIfPresent(extensionsResult);
    isolate.extensionRPCs.addAll(
        (extensionsResult.result['result']['value'] as List).cast<String>());

    // TODO: What about `architectureBits`, `targetCPU`, `hostCPU` and `pid`?
    final vm = VM()
      ..isolates = [isolateRef]
      ..name = 'ChromeDebugProxy'
      ..startTime = DateTime.now().millisecondsSinceEpoch
      ..version = Platform.version;

    return ChromeProxyService._(vm, isolate, tabConnection, assetHandler);
  }

  @override
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) {
    throw UnimplementedError();
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
        await _tabConnection.runtime.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'awaitPromise': true,
    });
    _handleErrorIfPresent(response);
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
      {Map<String, String> scope}) async {
    var library = await _getLibrary(isolateId, targetId);
    if (library == null) {
      throw UnsupportedError(
          'Evaluate is only supported when `targetId` is a library.');
    }
    var result = await _tabConnection.runtime.evaluate('''
(function() {
  ${_getLibrarySnippet(library.uri)};
  return library.$expression;
})();
    ''');

    String kind;
    var classRef = ClassRef()
      ..id = 'dart:core:${result.type}'
      ..name = result.type;
    switch (result.type) {
      case 'string':
        kind = InstanceKind.kString;
        break;
      case 'number':
        kind = InstanceKind.kDouble;
        break;
      case 'boolean':
        kind = InstanceKind.kBool;
        break;
      default:
        throw UnsupportedError('Unsupported response type ${result.type}');
    }

    return InstanceRef()
      ..valueAsString = '${result.value}'
      ..classRef = classRef
      ..kind = kind;
  }

  @override
  Future evaluateInFrame(String isolateId, int frameIndex, String expression,
      {Map<String, String> scope}) {
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
    if (_isolate.id == isolateId) return _isolate;
    throw ArgumentError.value(
        isolateId, 'isolateId', 'Unrecognized isolate id');
  }

  @override
  Future getIsolate(String isolateId) async => _getIsolate(isolateId);

  LibraryRef _getLibraryRef(String isolateId, String objectId) {
    // TODO(grouma) - We should get a set of LibraryRefs to improve performance.
    return _getIsolate(isolateId)
        .libraries
        .firstWhere((l) => l.id == objectId, orElse: () => null);
  }

  Future<Library> _getLibrary(String isolateId, String objectId) async {
    return _libraries.putIfAbsent(objectId, () async {
      var libraryRef = _getLibraryRef(isolateId, objectId);
      if (libraryRef == null) return null;

      // Fetch information about all the classes in this library.
      var expression = '''
(function() {
${_getLibrarySnippet(libraryRef.uri)}
  var classes = Object.values(library)
    .filter((l) => l && sdkUtils.isType(l));
  return classes.map(function(clazz) {
    var description = {'name': clazz.name};
    var methods = sdkUtils.getMethods(clazz);
    description['methods'] = methods ? Object.keys(methods) : [];
    return description;
  });
})()
''';
      var classesResult = await _tabConnection.runtime.sendCommand(
          'Runtime.evaluate',
          params: {'expression': expression, 'returnByValue': true});
      _handleErrorIfPresent(classesResult);
      var classDescriptions = (classesResult.result['result']['value'] as List)
          .cast<Map<String, Object>>();
      var classRefs = <ClassRef>[];
      for (var description in classDescriptions) {
        var name = description['name'] as String;
        var classId = '${libraryRef.id}:$name';
        var classRef = ClassRef()
          ..name = name
          ..id = classId;
        classRefs.add(classRef);

        var methodRefs = <FuncRef>[];

        // Add all instance methods, static methods aren't supported yet.
        var methodNames = (description['methods'] as List).cast<String>();
        for (var method in methodNames) {
          var methodId = '$classId:$method';
          methodRefs.add(FuncRef()
            ..id = methodId
            ..name = method
            ..owner = classRef
            ..isStatic = false);
        }

        // TODO: Implement the rest of these
        // https://github.com/dart-lang/webdev/issues/176.
        _classes[classId] = Class()
          ..classRef = classRef
          ..functions = methodRefs
          ..id = classId
          ..library = libraryRef
          ..name = name
          ..fields = []
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
    });
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
    var scripts = await _getScripts(isolateId);
    return ScriptList()..scripts = scripts;
  }

  Future<Script> _getScript(String isolateId, ScriptRef scriptRef) async {
    var libraryId = scriptRef.uri;
    var scriptPath = libraryId.replaceAll('package:', 'packages/');
    var script = await _assetHandler(scriptPath);
    return Script()
      ..library = _getLibraryRef(isolateId, libraryId)
      ..id = scriptRef.id
      ..uri = libraryId
      // TODO(grouma) - Fill in to enable break points.
      ..tokenPosTable = []
      ..source = script;
  }

  Future<List<ScriptRef>> _getScripts(String isolateId) async {
    var isolate = _getIsolate(isolateId);
    var scripts = <ScriptRef>[];
    for (var lib in isolate.libraries) {
      // We can't provide the source for `dart:` imports so ignore for now.
      // Also `main.dart.bootstrap` does not have a corresponding script.
      if (lib.id.startsWith('dart:') || lib.id.endsWith('.bootstrap')) continue;
      scripts.addAll((await _getLibrary(isolateId, lib.id)).scripts);
    }
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
      List<String> argumentIds) {
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
  Future<Success> pause(String isolateId) {
    throw UnimplementedError();
  }

  @override
  // TODO: what does `alias` represent here?
  Future<Success> registerService(String service, String alias) async {
    _isolate.extensionRPCs.add(service);
    _streamNotify(
        '_Service',
        Event()
          ..kind = EventKind.kServiceRegistered
          ..extensionRPC = service);
    return Success();
  }

  @override
  Future<ReloadReport> reloadSources(String isolateId,
      {bool force, bool pause, String rootLibUri, String packagesUri}) {
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
  Future<Success> resume(String isolateId, {String step, int frameIndex}) {
    throw UnimplementedError();
  }

  @override
  Future<Success> setExceptionPauseMode(String isolateId, String mode) {
    throw UnimplementedError();
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
    _streamNotify(
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
          _tabConnection.runtime.onConsoleAPICalled.listen((e) {
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
            _tabConnection.runtime.onExceptionThrown.listen((e) {
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
      pauseSubscription = _tabConnection.debugger.onPaused.listen((e) {
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
        _streamNotify('Debug', event);
      });
      resumeSubscription = _tabConnection.debugger.onResumed.listen((e) {
        _streamNotify(
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

  /// Adds [event] to the stream with [streamId] if there is anybody listening
  /// on that stream.
  void _streamNotify(String streamId, Event event) {
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
void _handleErrorIfPresent(WipResponse response) {
  if (response.result.containsKey('exceptionDetails')) {
    // ignore: only_throw_errors
    throw ExceptionDetails(
        response.result['exceptionDetails'] as Map<String, dynamic>);
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
