// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

// @dart = 2.9

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../connections/app_connection.dart';
import '../loaders/strategy.dart';
import '../readers/asset_reader.dart';
import '../utilities/conversions.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/sdk_configuration.dart';
import '../utilities/shared.dart';
import 'classes.dart';
import 'debugger.dart';
import 'execution_context.dart';
import 'instance.dart';
import 'libraries.dart';
import 'location.dart';
import 'remote_debugger.dart';

/// An inspector for a running Dart application contained in the
/// [WipConnection].
///
/// Provides information about currently loaded scripts and objects and support
/// for eval.
class AppInspector implements AppInspectorInterface {
  final _scriptCacheMemoizer = AsyncMemoizer<List<ScriptRef>>();

  Future<List<ScriptRef>> get scriptRefs => _populateScriptCaches();

  final _logger = Logger('AppInspector');

  /// Map of scriptRef ID to [ScriptRef].
  final _scriptRefsById = <String, ScriptRef>{};

  /// Map of Dart server path to [ScriptRef].
  final _serverPathToScriptRef = <String, ScriptRef>{};

  /// Map of [ScriptRef] id to containing [LibraryRef] id.
  final _scriptIdToLibraryId = <String, String>{};

  /// Map of [Library] id to included [ScriptRef]s.
  final _libraryIdToScriptRefs = <String, List<ScriptRef>>{};

  final RemoteDebugger _remoteDebugger;
  @override
  RemoteDebugger get remoteDebugger => _remoteDebugger;

  final Isolate _isolate;
  @override
  Isolate get isolate => _isolate;

  final IsolateRef _isolateRef;
  @override
  IsolateRef get isolateRef => _isolateRef;

  final AppConnection _appConnection;
  @override
  AppConnection get appConnection => _appConnection;

  final ExecutionContext _executionContext;

  LibraryHelper _libraryHelper;
  ClassHelper _classHelper;
  InstanceHelper _instanceHelper;

  final AssetReader _assetReader;
  final Locations _locations;

  /// The root URI from which the application is served.
  final String _root;
  final SdkConfiguration _sdkConfiguration;

  /// JavaScript expression that evaluates to the Dart stack trace mapper.
  static const stackTraceMapperExpression = '\$dartStackTraceUtility.mapper';

  /// Regex used to extract the message from an exception description.
  static final exceptionMessageRegex = RegExp(r'^.*$', multiLine: true);

  AppInspector._(
    this._appConnection,
    this._isolate,
    this._remoteDebugger,
    this._assetReader,
    this._locations,
    this._root,
    this._executionContext,
    this._sdkConfiguration,
  ) : _isolateRef = _toIsolateRef(_isolate);

  Future<void> initialize(
    LibraryHelper libraryHelper,
    ClassHelper classHelper,
    InstanceHelper instanceHelper,
  ) async {
    _libraryHelper = libraryHelper;
    _classHelper = classHelper;
    _instanceHelper = instanceHelper;

    final libraries = await _libraryHelper.libraryRefs;
    isolate.rootLib = await _libraryHelper.rootLib;
    isolate.libraries.addAll(libraries);

    final scripts = await scriptRefs;

    await DartUri.initialize(_sdkConfiguration);
    await DartUri.recordAbsoluteUris(libraries.map((lib) => lib.uri));
    await DartUri.recordAbsoluteUris(scripts.map((script) => script.uri));

    isolate.extensionRPCs.addAll(await _getExtensionRpcs());
  }

  static IsolateRef _toIsolateRef(Isolate isolate) => IsolateRef(
        id: isolate.id,
        name: isolate.name,
        number: isolate.number,
        isSystemIsolate: isolate.isSystemIsolate,
      );

  static Future<AppInspector> create(
    AppConnection appConnection,
    RemoteDebugger remoteDebugger,
    AssetReader assetReader,
    Locations locations,
    String root,
    Debugger debugger,
    ExecutionContext executionContext,
    SdkConfiguration sdkConfiguration,
  ) async {
    final id = createId();
    final time = DateTime.now().millisecondsSinceEpoch;
    final name = 'main()';
    final isolate = Isolate(
        id: id,
        number: id,
        name: name,
        startTime: time,
        runnable: true,
        pauseOnExit: false,
        pauseEvent: Event(
            kind: EventKind.kPauseStart,
            timestamp: time,
            isolate: IsolateRef(
              id: id,
              name: name,
              number: id,
              isSystemIsolate: false,
            )),
        livePorts: 0,
        libraries: [],
        breakpoints: [],
        exceptionPauseMode: debugger.pauseState,
        isSystemIsolate: false,
        isolateFlags: [])
      ..extensionRPCs = [];
    final inspector = AppInspector._(
      appConnection,
      isolate,
      remoteDebugger,
      assetReader,
      locations,
      root,
      executionContext,
      sdkConfiguration,
    );

    debugger.updateInspector(inspector);

    final libraryHelper = LibraryHelper(inspector);
    final classHelper = ClassHelper(inspector);
    final instanceHelper = InstanceHelper(inspector, debugger);

    await inspector.initialize(
      libraryHelper,
      classHelper,
      instanceHelper,
    );
    return inspector;
  }

  /// Returns the ID for the execution context or null if not found.
  @override
  Future<int> get contextId async {
    try {
      return await _executionContext.id;
    } catch (e, s) {
      _logger.severe('Missing execution context ID: ', e, s);
      return null;
    }
  }

  /// Get the value of the field named [fieldName] from [receiver].
  @override
  Future<RemoteObject> loadField(RemoteObject receiver, String fieldName) {
    final load = '''
        function() {
          return ${globalLoadStrategy.loadModuleSnippet}("dart_sdk").dart.dloadRepl(this, "$fieldName");
        }
        ''';
    return jsCallFunctionOn(receiver, load, []);
  }

  /// Call a method by name on [receiver], with arguments [positionalArgs] and
  /// [namedArgs].
  Future<RemoteObject> _invokeMethod(RemoteObject receiver, String methodName,
      [List<RemoteObject> positionalArgs = const [],
      Map namedArgs = const {}]) async {
    // TODO(alanknight): Support named arguments.
    if (namedArgs.isNotEmpty) {
      throw UnsupportedError('Named arguments are not yet supported');
    }
    // We use the JS pseudo-variable 'arguments' to get the list of all arguments.
    final send = '''
        function () {
          if (!(this.__proto__)) { return 'Instance of PlainJavaScriptObject';}
          return ${globalLoadStrategy.loadModuleSnippet}("dart_sdk").dart.dsendRepl(this, "$methodName", arguments);
        }
        ''';
    final remote = await jsCallFunctionOn(receiver, send, positionalArgs);
    return remote;
  }

  /// Calls Chrome's Runtime.callFunctionOn method.
  ///
  /// [evalExpression] should be a JS function definition that can accept
  /// [arguments].
  @override
  Future<RemoteObject> jsCallFunctionOn(RemoteObject receiver,
      String evalExpression, List<RemoteObject> arguments,
      {bool returnByValue = false}) async {
    final jsArguments = arguments.map(callArgumentFor).toList();
    final result =
        await remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
      'functionDeclaration': evalExpression,
      'arguments': jsArguments,
      'objectId': receiver.objectId,
      'returnByValue': returnByValue,
    });
    handleErrorIfPresent(result, evalContents: evalExpression);
    return RemoteObject(result.result['result'] as Map<String, Object>);
  }

  /// Calls Chrome's Runtime.callFunctionOn method with a global function.
  ///
  /// [evalExpression] should be a JS function definition that can accept
  /// [arguments].
  Future<RemoteObject> _jsCallFunction(
      String evalExpression, List<Object> arguments,
      {bool returnByValue = false}) async {
    final jsArguments = arguments.map(callArgumentFor).toList();
    final result =
        await remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
      'functionDeclaration': evalExpression,
      'arguments': jsArguments,
      'executionContextId': await contextId,
      'returnByValue': returnByValue,
    });
    handleErrorIfPresent(result, evalContents: evalExpression);
    return RemoteObject(result.result['result'] as Map<String, Object>);
  }

  /// Invoke the function named [selector] on the object identified by
  /// [targetId].
  ///
  /// The [targetId] can be the URL of a Dart library, in which case this means
  /// invoking a top-level function. The [arguments] are always strings that are
  /// Dart object Ids (which can also be Chrome RemoteObject objectIds that are
  /// for non-Dart JS objects.)
  @override
  Future<RemoteObject> invoke(
      String targetId, String selector, List<dynamic> arguments) async {
    final remoteArguments =
        arguments.cast<String>().map(remoteObjectFor).toList();
    // We special case the Dart library, where invokeMethod won't work because
    // it's not really a Dart object.
    if (isLibraryId(targetId)) {
      final library = await getObject(targetId) as Library;
      return await _invokeLibraryFunction(library, selector, remoteArguments);
    } else {
      return _invokeMethod(
          remoteObjectFor(targetId), selector, remoteArguments);
    }
  }

  /// Invoke the function named [selector] from [library] with [arguments].
  Future<RemoteObject> _invokeLibraryFunction(
      Library library, String selector, List<RemoteObject> arguments) {
    return _evaluateInLibrary(
        library,
        'function () { return this.$selector.apply(this, arguments);}',
        arguments);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluate.
  @override
  Future<RemoteObject> jsEvaluate(String expression,
      {bool awaitPromise = false}) async {
    // TODO(alanknight): Support a version with arguments if needed.
    WipResponse result;
    result = await remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'awaitPromise': awaitPromise,
      'contextId': await contextId,
    });
    handleErrorIfPresent(result, evalContents: expression, additionalDetails: {
      'Dart expression': expression,
    });
    return RemoteObject(result.result['result'] as Map<String, dynamic>);
  }

  /// Evaluate the JS function with source [jsFunction] in the context of
  /// [library] with [arguments].
  Future<RemoteObject> _evaluateInLibrary(
      Library library, String jsFunction, List<RemoteObject> arguments) async {
    final findLibrary = '''
(function() {
  ${globalLoadStrategy.loadLibrarySnippet(library.uri)};
  return library;
})();
''';
    final remoteLibrary = await jsEvaluate(findLibrary);
    return jsCallFunctionOn(remoteLibrary, jsFunction, arguments);
  }

  /// Call [function] with objects referred by [argumentIds] as arguments.
  @override
  Future<RemoteObject> callFunction(
      String function, Iterable<String> argumentIds) async {
    final arguments = argumentIds.map(remoteObjectFor).toList();
    return _jsCallFunction(function, arguments);
  }

  @override
  Future<InstanceRef> instanceRefFor(Object value) =>
      _instanceHelper.instanceRefFor(value);

  Future<Instance> instanceFor(Object value) =>
      _instanceHelper.instanceFor(value);

  @override
  Future<LibraryRef> libraryRefFor(String objectId) =>
      _libraryHelper.libraryRefFor(objectId);

  @override
  Future<Library> getLibrary(String objectId) async {
    final libraryRef = await libraryRefFor(objectId);
    if (libraryRef == null) return null;
    return _libraryHelper.libraryFor(libraryRef);
  }

  @override
  Future<Obj> getObject(String objectId, {int offset, int count}) async {
    try {
      final library = await getLibrary(objectId);
      if (library != null) {
        return library;
      }
      final clazz = await _classHelper.forObjectId(objectId);
      if (clazz != null) {
        return clazz;
      }
      final scriptRef = _scriptRefsById[objectId];
      if (scriptRef != null) {
        return await _getScript(scriptRef);
      }
      final instance = await _instanceHelper
          .instanceFor(remoteObjectFor(objectId), offset: offset, count: count);
      if (instance != null) {
        return instance;
      }
    } catch (e, s) {
      _logger.fine('getObject $objectId failed', e, s);
      rethrow;
    }
    throw UnsupportedError('Only libraries, instances, classes, and scripts '
        'are supported for getObject');
  }

  Future<Script> _getScript(ScriptRef scriptRef) async {
    final libraryId = _scriptIdToLibraryId[scriptRef.id];
    final serverPath = DartUri(scriptRef.uri, _root).serverPath;
    final source = await _assetReader.dartSourceContents(serverPath);
    if (source == null) {
      throw RPCError('getObject', RPCError.kInvalidParams,
          'Failed to load script at path: $serverPath');
    }
    return Script(
        uri: scriptRef.uri,
        library: await libraryRefFor(libraryId),
        id: scriptRef.id)
      ..tokenPosTable = await _locations.tokenPosTableFor(serverPath)
      ..source = source;
  }

  @override
  Future<MemoryUsage> getMemoryUsage() async {
    final response = await remoteDebugger.sendCommand('Runtime.getHeapUsage');

    final jsUsage = HeapUsage(response.result);
    return MemoryUsage.parse({
      'heapUsage': jsUsage.usedSize,
      'heapCapacity': jsUsage.totalSize,
      'externalUsage': 0,
    });
  }

  /// Returns the [ScriptRef] for the provided Dart server path [uri].
  @override
  Future<ScriptRef> scriptRefFor(String uri) async {
    await _populateScriptCaches();
    return _serverPathToScriptRef[uri];
  }

  /// Returns the [ScriptRef]s in the library with [libraryId].
  @override
  Future<List<ScriptRef>> scriptRefsForLibrary(String libraryId) async {
    await _populateScriptCaches();
    return _libraryIdToScriptRefs[libraryId];
  }

  /// Return the VM SourceReport for the given parameters.
  ///
  /// Currently this implements the 'PossibleBreakpoints' report kind.
  @override
  Future<SourceReport> getSourceReport(
    List<String> reports, {
    String scriptId,
    int tokenPos,
    int endTokenPos,
    bool forceCompile,
    bool reportLines,
    List<String> libraryFilters,
  }) {
    if (reports.contains(SourceReportKind.kCoverage)) {
      throwInvalidParam('getSourceReport',
          'Source report kind ${SourceReportKind.kCoverage} not supported');
    }

    if (reports.isEmpty) {
      throwInvalidParam('getSourceReport',
          'Invalid parameter: no value for source report kind provided.');
    }

    if (reports.length > 1 ||
        reports.first != SourceReportKind.kPossibleBreakpoints) {
      throwInvalidParam('getSourceReport', 'Unsupported source report kind.');
    }

    return _getPossibleBreakpoints(scriptId);
  }

  Future<SourceReport> _getPossibleBreakpoints(String scriptId) async {
    // TODO(devoncarew): Consider adding some caching for this method.

    final scriptRef = scriptWithId(scriptId);
    if (scriptRef == null) {
      throwInvalidParam('getSourceReport', 'scriptId not found: $scriptId');
    }

    final dartUri = DartUri(scriptRef.uri, _root);
    final mappedLocations =
        await _locations.locationsForDart(dartUri.serverPath);
    // Unlike the Dart VM, the token positions match exactly to the possible
    // breakpoints. This is because the token positions are derived from the
    // DDC source maps which Chrome also uses.
    final tokenPositions = <int>[
      for (var location in mappedLocations) location.tokenPos
    ];
    tokenPositions.sort();

    final range = SourceReportRange(
      scriptIndex: 0,
      startPos: tokenPositions.isEmpty ? -1 : tokenPositions.first,
      endPos: tokenPositions.isEmpty ? -1 : tokenPositions.last,
      compiled: true,
      possibleBreakpoints: tokenPositions,
    );

    final ranges = [range];
    return SourceReport(scripts: [scriptRef], ranges: ranges);
  }

  /// All the scripts in the isolate.
  @override
  Future<ScriptList> getScripts() async {
    return ScriptList(scripts: await scriptRefs);
  }

  /// Request and cache <ScriptRef>s for all the scripts in the application.
  ///
  /// This populates [_scriptRefsById], [_scriptIdToLibraryId],
  /// [_libraryIdToScriptRefs] and [_serverPathToScriptRef].
  ///
  /// It is a one-time operation, because if we do a
  /// reload the inspector will get re-created.
  ///
  /// Returns the list of scripts refs cached.
  Future<List<ScriptRef>> _populateScriptCaches() async {
    return _scriptCacheMemoizer.runOnce(() async {
      final libraryUris = [for (var library in isolate.libraries) library.uri];
      final scripts = await globalLoadStrategy
          .metadataProviderFor(appConnection.request.entrypointPath)
          .scripts;
      // For all the non-dart: libraries, find their parts and create scriptRefs
      // for them.
      final userLibraries =
          libraryUris.where((uri) => !uri.startsWith('dart:'));
      for (var uri in userLibraries) {
        final parts = scripts[uri];
        final scriptRefs = [
          ScriptRef(uri: uri, id: createId()),
          for (var part in parts) ScriptRef(uri: part, id: createId())
        ];
        final libraryRef = await _libraryHelper.libraryRefFor(uri);
        _libraryIdToScriptRefs.putIfAbsent(libraryRef.id, () => <ScriptRef>[]);
        for (var scriptRef in scriptRefs) {
          _scriptRefsById[scriptRef.id] = scriptRef;
          _scriptIdToLibraryId[scriptRef.id] = libraryRef.id;
          _serverPathToScriptRef[DartUri(scriptRef.uri, _root).serverPath] =
              scriptRef;
          _libraryIdToScriptRefs[libraryRef.id].add(scriptRef);
        }
      }
      return _scriptRefsById.values.toList();
    });
  }

  /// Look up the script by id in an isolate.
  @override
  ScriptRef scriptWithId(String scriptId) => _scriptRefsById[scriptId];

  /// Runs an eval on the page to compute all existing registered extensions.
  Future<List<String>> _getExtensionRpcs() async {
    final expression =
        "${globalLoadStrategy.loadModuleSnippet}('dart_sdk').developer._extensions.keys.toList();";
    final extensionRpcs = <String>[];
    final params = {
      'expression': expression,
      'returnByValue': true,
      'contextId': await contextId,
    };
    try {
      final extensionsResult =
          await remoteDebugger.sendCommand('Runtime.evaluate', params: params);
      handleErrorIfPresent(extensionsResult, evalContents: expression);
      extensionRpcs.addAll(
          List.from(extensionsResult.result['result']['value'] as List));
    } catch (e, s) {
      _logger.severe(
          'Error calling Runtime.evaluate with params $params', e, s);
    }
    return extensionRpcs;
  }

  /// Convert a JS exception description into a description containing
  /// a Dart stack trace.
  @override
  Future<String> mapExceptionStackTrace(String description) async {
    RemoteObject mapperResult;
    try {
      mapperResult = await _jsCallFunction(
          stackTraceMapperExpression, <Object>[description]);
    } catch (_) {
      return description;
    }
    final mappedStack = mapperResult?.value?.toString();
    if (mappedStack == null || mappedStack.isEmpty) {
      return description;
    }
    var message = exceptionMessageRegex.firstMatch(description)?.group(0);
    message = (message != null) ? '$message\n' : '';
    return '$message$mappedStack';
  }
}
