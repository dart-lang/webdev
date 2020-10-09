// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../connections/app_connection.dart';
import '../debugging/location.dart';
import '../debugging/remote_debugger.dart';
import '../loaders/strategy.dart';
import '../readers/asset_reader.dart';
import '../utilities/conversions.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/shared.dart';
import 'classes.dart';
import 'debugger.dart';
import 'execution_context.dart';
import 'instance.dart';
import 'libraries.dart';

/// An inspector for a running Dart application contained in the
/// [WipConnection].
///
/// Provides information about currently loaded scripts and objects and support
/// for eval.
class AppInspector extends Domain {
  Future<List<ScriptRef>> _cachedScriptRefs;

  Future<List<ScriptRef>> get scriptRefs => _cachedScriptRefs ??= _getScripts();

  /// Map of scriptRef ID to [ScriptRef].
  final _scriptRefsById = <String, ScriptRef>{};

  /// Map of Dart server path to [ScriptRef].
  final _serverPathToScriptRef = <String, ScriptRef>{};

  /// Map of [ScriptRef] id to containing [LibraryRef] id.
  final _scriptIdToLibraryId = <String, String>{};

  final RemoteDebugger remoteDebugger;
  final Debugger debugger;
  final Isolate isolate;
  final IsolateRef isolateRef;
  final AppConnection appConnection;
  final ExecutionContext _executionContext;

  final LibraryHelper libraryHelper;
  final ClassHelper classHelper;
  final InstanceHelper instanceHelper;

  final AssetReader _assetReader;
  final Locations _locations;

  /// The root URI from which the application is served.
  final String _root;

  AppInspector._(
    this.appConnection,
    this.isolate,
    this.remoteDebugger,
    this.debugger,
    this.libraryHelper,
    this.classHelper,
    this.instanceHelper,
    this._assetReader,
    this._locations,
    this._root,
    this._executionContext,
  )   : isolateRef = _toIsolateRef(isolate),
        super.forInspector();

  /// We are the inspector, so this getter is trivial.
  @override
  AppInspector get inspector => this;

  Future<void> _initialize() async {
    var libraries = await libraryHelper.libraryRefs;
    isolate.libraries.addAll(libraries);

    await DartUri.recordAbsoluteUris(libraries.map((lib) => lib.uri));

    // This relies on the convention that the 2nd to last library is the root
    // library (and the last one is the bootstrap library).
    if (libraries.length >= 2) {
      isolate.rootLib = libraries[libraries.length - 2];
    } else {
      isolate.rootLib = libraries.last;
    }

    isolate.extensionRPCs.addAll(await _getExtensionRpcs());
  }

  static IsolateRef _toIsolateRef(Isolate isolate) => IsolateRef(
        id: isolate.id,
        name: isolate.name,
        number: isolate.number,
        isSystemIsolate: isolate.isSystemIsolate,
      );

  static Future<AppInspector> initialize(
    AppConnection appConnection,
    RemoteDebugger remoteDebugger,
    AssetReader assetReader,
    Locations locations,
    String root,
    Debugger debugger,
    ExecutionContext executionContext,
  ) async {
    var id = createId();
    var time = DateTime.now().millisecondsSinceEpoch;
    var name = 'main()';
    var isolate = Isolate(
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
        isSystemIsolate: false)
      ..extensionRPCs = [];
    AppInspector appInspector;
    var provider = () => appInspector;
    var libraryHelper = LibraryHelper(provider);
    var classHelper = ClassHelper(provider);
    var instanceHelper = InstanceHelper(provider);
    appInspector = AppInspector._(
      appConnection,
      isolate,
      remoteDebugger,
      debugger,
      libraryHelper,
      classHelper,
      instanceHelper,
      assetReader,
      locations,
      root,
      executionContext,
    );
    await appInspector._initialize();
    return appInspector;
  }

  Future<int> get contextId => _executionContext.id;

  /// Get the value of the field named [fieldName] from [receiver].
  Future<RemoteObject> loadField(RemoteObject receiver, String fieldName) {
    var load = '''
        function() {
          return ${globalLoadStrategy.loadModuleSnippet}("dart_sdk").dart.dloadRepl(this, "$fieldName");
        }
        ''';
    return jsCallFunctionOn(receiver, load, []);
  }

  /// Call a method by name on [receiver], with arguments [positionalArgs] and
  /// [namedArgs].
  Future<RemoteObject> invokeMethod(RemoteObject receiver, String methodName,
      [List<RemoteObject> positionalArgs = const [],
      Map namedArgs = const {}]) async {
    // TODO(alanknight): Support named arguments.
    if (namedArgs.isNotEmpty) {
      throw UnsupportedError('Named arguments are not yet supported');
    }
    // We use the JS pseudo-variable 'arguments' to get the list of all arguments.
    var send = '''
        function () {
          if (!(this.__proto__)) { return 'Instance of PlainJavaScriptObject';}
          return ${globalLoadStrategy.loadModuleSnippet}("dart_sdk").dart.dsendRepl(this, "$methodName", arguments);
        }
        ''';
    var remote = await jsCallFunctionOn(receiver, send, positionalArgs);
    return remote;
  }

  /// Calls Chrome's Runtime.callFunctionOn method.
  ///
  /// [evalExpression] should be a JS function definition that can accept
  /// [arguments].
  Future<RemoteObject> jsCallFunctionOn(RemoteObject receiver,
      String evalExpression, List<RemoteObject> arguments,
      {bool returnByValue = false}) async {
    var jsArguments = arguments.map(callArgumentFor).toList();
    var result =
        await remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
      'functionDeclaration': evalExpression,
      'arguments': jsArguments,
      'objectId': receiver.objectId,
      'returnByValue': returnByValue,
    });
    handleErrorIfPresent(result, evalContents: evalExpression);
    return RemoteObject(result.result['result'] as Map<String, Object>);
  }

  Future<RemoteObject> evaluate(
      String isolateId, String targetId, String expression,
      {Map<String, String> scope}) async {
    scope ??= {};
    var library = await _getLibrary(isolateId, targetId);
    if (library == null) {
      throw UnsupportedError(
          'Evaluate is only supported when `targetId` is a library.');
    }
    if (scope.isNotEmpty) {
      return evaluateInLibrary(library, scope, expression);
    } else {
      return evaluateJsExpressionOnLibrary(expression, library.uri);
    }
  }

  /// Invoke the function named [selector] on the object identified by
  /// [targetId].
  ///
  /// The [targetId] can be the URL of a Dart library, in which case this means
  /// invoking a top-level function. The [arguments] are always strings that are
  /// Dart object Ids (which can also be Chrome RemoteObject objectIds that are
  /// for non-Dart JS objects.)
  Future<RemoteObject> invoke(String isolateId, String targetId,
      String selector, List<dynamic> arguments) async {
    checkIsolate('invoke', isolateId);
    var remoteArguments =
        arguments.cast<String>().map(remoteObjectFor).toList();
    // We special case the Dart library, where invokeMethod won't work because
    // it's not really a Dart object.
    if (isLibraryId(targetId)) {
      var library = await getObject(isolateId, targetId) as Library;
      return await _invokeLibraryFunction(library, selector, remoteArguments);
    } else {
      return invokeMethod(remoteObjectFor(targetId), selector, remoteArguments);
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

  /// Evaluate [expression] as a member/message of the library identified by
  /// [libraryUri].
  ///
  /// That is, we will just do 'library.$expression'
  Future<RemoteObject> evaluateJsExpressionOnLibrary(
      String expression, String libraryUri) {
    var evalExpression = '''
(function() {
  ${globalLoadStrategy.loadLibrarySnippet(libraryUri)};
  return library.$expression;
})();
''';
    return jsEvaluate(evalExpression);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluate.
  Future<RemoteObject> jsEvaluate(String expression) async {
    // TODO(alanknight): Support a version with arguments if needed.
    WipResponse result;
    result = await remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
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
    var findLibrary = '''
(function() {
  ${globalLoadStrategy.loadLibrarySnippet(library.uri)};
  return library;
})();
''';
    var remoteLibrary = await jsEvaluate(findLibrary);
    return jsCallFunctionOn(remoteLibrary, jsFunction, arguments);
  }

  /// Evaluate [expression] from [library] with [scope] as
  /// arguments.
  Future<RemoteObject> evaluateInLibrary(
      Library library, Map<String, String> scope, String expression) async {
    var argsString = scope.keys.join(', ');
    var arguments = scope.values.map(remoteObjectFor).toList();
    var evalExpression = '''
function($argsString) {
  ${globalLoadStrategy.loadLibrarySnippet(library.uri)};
  return library.$expression;
}
    ''';
    return _evaluateInLibrary(library, evalExpression, arguments);
  }

  Future<Library> _getLibrary(String isolateId, String objectId) async {
    if (isolateId != isolate.id) return null;
    var libraryRef = await libraryHelper.libraryRefFor(objectId);
    if (libraryRef == null) return null;
    return libraryHelper.libraryFor(libraryRef);
  }

  Future<Obj> getObject(String isolateId, String objectId,
      {int offset, int count}) async {
    var library = await _getLibrary(isolateId, objectId);
    if (library != null) return library;
    var clazz = await classHelper.forObjectId(objectId);
    if (clazz != null) return clazz;
    var scriptRef = _scriptRefsById[objectId];
    if (scriptRef != null) return await _getScript(isolateId, scriptRef);
    var instance = await instanceHelper.instanceFor(remoteObjectFor(objectId),
        offset: offset, count: count);
    if (instance != null) return instance;
    throw UnsupportedError('Only libraries, instances, classes, and scripts '
        'are supported for getObject');
  }

  Future<Script> _getScript(String isolateId, ScriptRef scriptRef) async {
    var libraryId = _scriptIdToLibraryId[scriptRef.id];
    var serverPath = DartUri(scriptRef.uri, _root).serverPath;
    var source = await _assetReader.dartSourceContents(serverPath);
    if (source == null) {
      throw RPCError('getObject', RPCError.kInvalidParams,
          'Failed to load script at path: $serverPath');
    }
    return Script(
        uri: scriptRef.uri,
        library: await libraryHelper.libraryRefFor(libraryId),
        id: scriptRef.id)
      ..tokenPosTable = await _locations.tokenPosTableFor(serverPath)
      ..source = source;
  }

  Future<MemoryUsage> getMemoryUsage(String isolateId) async {
    checkIsolate('getMemoryUsage', isolateId);

    final response = await remoteDebugger.sendCommand('Runtime.getHeapUsage');

    final jsUsage = HeapUsage(response.result);
    return MemoryUsage.parse({
      'heapUsage': jsUsage.usedSize,
      'heapCapacity': jsUsage.totalSize,
      'externalUsage': 0,
    });
  }

  /// Returns the [ScriptRef] for the provided Dart server path [uri].
  Future<ScriptRef> scriptRefFor(String uri) async {
    if (_serverPathToScriptRef.isEmpty) {
      // TODO(grouma) - populate the server path cache a better way.
      await getScripts(isolate.id);
    }
    return _serverPathToScriptRef[uri];
  }

  /// Return the VM SourceReport for the given parameters.
  ///
  /// Currently this implements the 'PossibleBreakpoints' report kind.
  Future<SourceReport> getSourceReport(String isolateId, List<String> reports,
      {String scriptId, int tokenPos, int endTokenPos, bool forceCompile}) {
    checkIsolate('getSourceReport', isolateId);

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

    return _getPossibleBreakpoints(isolateId, scriptId);
  }

  Future<SourceReport> _getPossibleBreakpoints(
      String isolateId, String vmScriptId) async {
    // TODO(devoncarew): Consider adding some caching for this method.

    final scriptRef = scriptWithId(vmScriptId);
    if (scriptRef == null) {
      throwInvalidParam('getSourceReport', 'scriptId not found: $vmScriptId');
    }

    final dartUri = DartUri(scriptRef.uri, _root);
    final mappedLocations =
        await _locations.locationsForDart(dartUri.serverPath);
    // Unlike the Dart VM, the token positions match exactly to the possible
    // breakpoints. This is because the token positions are derived from the
    // DDC source maps which Chrome also uses.
    var tokenPositions = <int>[
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
  Future<ScriptList> getScripts(String isolateId) async {
    checkIsolate('getScripts', isolateId);
    return ScriptList(scripts: await scriptRefs);
  }

  Future<List<ScriptRef>> _getScripts() async {
    await _populateScriptCaches();
    return _scriptRefsById.values.toList();
  }

  /// Request and cache <ScriptRef>s for all the scripts in the application.
  ///
  /// This populates [_scriptRefsById], [_scriptIdToLibraryId] and
  /// [_serverPathToScriptRef]. It is a one-time operation, because if we do a
  /// reload the inspector will get re-created.
  Future<void> _populateScriptCaches() async {
    var libraryUris = [for (var library in isolate.libraries) library.uri];
    var scripts = await globalLoadStrategy
        .metadataProviderFor(appConnection.request.entrypointPath)
        .scripts;
    // For all the non-dart: libraries, find their parts and create scriptRefs
    // for them.
    var userLibraries = libraryUris.where((uri) => !uri.startsWith('dart:'));
    for (var uri in userLibraries) {
      var parent = uri.substring(0, uri.lastIndexOf('/'));
      var parts = scripts[uri];
      var scriptRefs = [
        ScriptRef(uri: uri, id: createId()),
        for (var part in parts)
          ScriptRef(uri: p.url.join(parent, part), id: createId())
      ];
      var libraryRef = await libraryHelper.libraryRefFor(uri);
      for (var scriptRef in scriptRefs) {
        _scriptRefsById[scriptRef.id] = scriptRef;
        _scriptIdToLibraryId[scriptRef.id] = libraryRef.id;
        _serverPathToScriptRef[DartUri(scriptRef.uri, _root).serverPath] =
            scriptRef;
      }
    }
  }

  /// Look up the script by id in an isolate.
  ScriptRef scriptWithId(String scriptId) => _scriptRefsById[scriptId];

  /// Runs an eval on the page to compute all existing registered extensions.
  Future<List<String>> _getExtensionRpcs() async {
    var expression =
        "${globalLoadStrategy.loadModuleSnippet}('dart_sdk').developer._extensions.keys.toList();";
    var extensionsResult =
        await remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'contextId': await contextId,
    });
    handleErrorIfPresent(extensionsResult, evalContents: expression);
    return List.from(extensionsResult.result['result']['value'] as List);
  }
}
