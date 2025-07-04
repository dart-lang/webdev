// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math' as math;

import 'package:async/async.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/debugging/classes.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/libraries.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/loaders/ddc_library_bundle.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/utilities/conversions.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:dwds/src/utilities/objects.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// An inspector for a running Dart application contained in the
/// [WipConnection].
///
/// Provides information about currently loaded scripts and objects and support
/// for eval.
class AppInspector implements AppInspectorInterface {
  var _scriptCacheMemoizer = AsyncMemoizer<List<ScriptRef>>();

  Future<List<ScriptRef>> getScriptRefs({
    ModifiedModuleReport? modifiedModuleReport,
  }) => _populateScriptCaches(modifiedModuleReport: modifiedModuleReport);

  final _logger = Logger('AppInspector');

  /// Map of scriptRef ID to [ScriptRef].
  final _scriptRefsById = <String, ScriptRef>{};

  /// Map of Dart server path to [ScriptRef].
  final _serverPathToScriptRef = <String, ScriptRef>{};

  /// Map of [ScriptRef] id to containing [LibraryRef] id.
  final _scriptIdToLibraryId = <String, String>{};

  /// Map of [Library] id to included [ScriptRef]s.
  final _libraryIdToScriptRefs = <String, List<ScriptRef>>{};

  @override
  RemoteDebugger get remoteDebugger => _remoteDebugger;
  final RemoteDebugger _remoteDebugger;

  @override
  Isolate get isolate => _isolate;
  final Isolate _isolate;

  @override
  IsolateRef get isolateRef => _isolateRef;
  final IsolateRef _isolateRef;

  @override
  AppConnection get appConnection => _appConnection;
  final AppConnection _appConnection;

  final ExecutionContext _executionContext;

  late LibraryHelper _libraryHelper;
  late ClassHelper _classHelper;
  late InstanceHelper _instanceHelper;

  final AssetReader _assetReader;
  final Locations _locations;

  /// The root URI from which the application is served.
  final String _root;

  /// JavaScript expression that evaluates to the Dart stack trace mapper.
  static const stackTraceMapperExpression = '\$dartStackTraceUtility.mapper';

  /// Regex used to extract the message from an exception description.
  static final exceptionMessageRegex = RegExp(r'^.*$', multiLine: true);

  /// Flutter widget inspector library.
  Future<LibraryRef?> get flutterWidgetInspectorLibrary => _libraryHelper
      .libraryRefFor('package:flutter/src/widgets/widget_inspector.dart');

  /// Regex used to extract a stack trace line from the exception description.
  static final stackTraceLineRegex = RegExp(r'^\s*at\s.*$', multiLine: true);

  AppInspector._(
    this._appConnection,
    this._isolate,
    this._remoteDebugger,
    this._assetReader,
    this._locations,
    this._root,
    this._executionContext,
  ) : _isolateRef = _toIsolateRef(_isolate);

  /// Reset all caches and recompute any mappings.
  ///
  /// Should be called across hot reloads with a valid [ModifiedModuleReport].
  Future<void> initialize({ModifiedModuleReport? modifiedModuleReport}) async {
    _scriptCacheMemoizer = AsyncMemoizer<List<ScriptRef>>();

    // TODO(srujzs): We can invalidate these in a smarter way instead of
    // reinitializing when doing a hot reload, but these helpers recompute info
    // on demand later and therefore are not in the critical path.
    _classHelper = ClassHelper(this);
    _instanceHelper = InstanceHelper(this);

    if (modifiedModuleReport != null) {
      // Invalidate `_libraryHelper` as we use it populate any script caches.
      _libraryHelper.initialize(modifiedModuleReport: modifiedModuleReport);
    } else {
      _libraryHelper = LibraryHelper(this)..initialize();
      _scriptRefsById.clear();
      _serverPathToScriptRef.clear();
      _scriptIdToLibraryId.clear();
      _libraryIdToScriptRefs.clear();
    }

    final libraries = await _libraryHelper.libraryRefs;
    isolate.rootLib = await _libraryHelper.rootLib;
    isolate.libraries?.clear();
    isolate.libraries?.addAll(libraries);

    final scripts = await getScriptRefs(
      modifiedModuleReport: modifiedModuleReport,
    );

    await DartUri.initialize();
    DartUri.recordAbsoluteUris(libraries.map((lib) => lib.uri).nonNulls);
    DartUri.recordAbsoluteUris(scripts.map((script) => script.uri).nonNulls);
    await getExtensionRpcs();
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
        ),
      ),
      livePorts: 0,
      libraries: [],
      breakpoints: [],
      exceptionPauseMode: debugger.pauseState,
      isSystemIsolate: false,
      isolateFlags: [],
    )..extensionRPCs = [];
    final inspector = AppInspector._(
      appConnection,
      isolate,
      remoteDebugger,
      assetReader,
      locations,
      root,
      executionContext,
    );

    debugger.updateInspector(inspector);
    await inspector.initialize();
    return inspector;
  }

  /// Returns the ID for the execution context or null if not found.
  @override
  Future<int?> get contextId async {
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
    final load = globalToolConfiguration.loadStrategy.dartRuntimeDebugger
        .getPropertyJsExpression(fieldName);
    return jsCallFunctionOn(receiver, load, []);
  }

  /// Call a method by name on [receiver], with arguments [positionalArgs] and
  /// [namedArgs].
  Future<RemoteObject> _invokeMethod(
    RemoteObject receiver,
    String methodName, [
    List<RemoteObject> positionalArgs = const [],
    Map namedArgs = const {},
  ]) async {
    // TODO(alanknight): Support named arguments.
    if (namedArgs.isNotEmpty) {
      throw UnsupportedError('Named arguments are not yet supported');
    }
    // We use the JS pseudo-variable 'arguments' to get the list of all arguments.
    final send = globalToolConfiguration.loadStrategy.dartRuntimeDebugger
        .callInstanceMethodJsExpression(methodName);
    final remote = await jsCallFunctionOn(receiver, send, positionalArgs);
    return remote;
  }

  /// Calls Chrome's Runtime.callFunctionOn method.
  ///
  /// [evalExpression] should be a JS function definition that can accept
  /// [arguments].
  @override
  Future<RemoteObject> jsCallFunctionOn(
    RemoteObject receiver,
    String evalExpression,
    List<RemoteObject> arguments, {
    bool returnByValue = false,
  }) async {
    final jsArguments = arguments.map(callArgumentFor).toList();
    final response = await remoteDebugger.sendCommand(
      'Runtime.callFunctionOn',
      params: {
        'functionDeclaration': evalExpression,
        'arguments': jsArguments,
        'objectId': receiver.objectId,
        'returnByValue': returnByValue,
      },
    );
    final result = getResultOrHandleError(
      response,
      evalContents: evalExpression,
    );
    return RemoteObject(result);
  }

  /// Calls Chrome's Runtime.callFunctionOn method with a global function.
  ///
  /// [evalExpression] should be a JS function definition that can accept
  /// [arguments].
  Future<RemoteObject> _jsCallFunction(
    String evalExpression,
    List<Object> arguments, {
    bool returnByValue = false,
  }) async {
    final jsArguments = arguments.map(callArgumentFor).toList();
    final response = await remoteDebugger.sendCommand(
      'Runtime.callFunctionOn',
      params: {
        'functionDeclaration': evalExpression,
        'arguments': jsArguments,
        'executionContextId': await contextId,
        'returnByValue': returnByValue,
      },
    );
    final result = getResultOrHandleError(
      response,
      evalContents: evalExpression,
    );
    return RemoteObject(result);
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
    String targetId,
    String selector, [
    List<dynamic> arguments = const [],
  ]) async {
    final remoteArguments =
        arguments.cast<String>().map(remoteObjectFor).toList();
    // We special case the Dart library, where invokeMethod won't work because
    // it's not really a Dart object.
    if (isLibraryId(targetId)) {
      final library = await getObject(targetId) as Library;
      return await _invokeLibraryFunction(library, selector, remoteArguments);
    } else {
      return _invokeMethod(
        remoteObjectFor(targetId),
        selector,
        remoteArguments,
      );
    }
  }

  /// Invoke the function named [selector] from [library] with [arguments].
  Future<RemoteObject> _invokeLibraryFunction(
    Library library,
    String selector,
    List<RemoteObject> arguments,
  ) {
    final libraryUri = library.uri;
    if (libraryUri == null) {
      throwInvalidParam('invoke', 'library uri is null');
    }
    return globalToolConfiguration.loadStrategy is DdcLibraryBundleStrategy
        ? _evaluateLibraryMethodWithDdcLibraryBundle(
          libraryUri,
          selector,
          arguments,
        )
        : _evaluateInLibrary(
          libraryUri,
          'function () { return this.$selector.apply(this, arguments); }',
          arguments,
        );
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluate.
  @override
  Future<RemoteObject> jsEvaluate(
    String expression, {
    bool returnByValue = false,
    bool awaitPromise = false,
  }) async {
    // TODO(alanknight): Support a version with arguments if needed.
    final response = await remoteDebugger.sendCommand(
      'Runtime.evaluate',
      params: {
        'expression': expression,
        'returnByValue': returnByValue,
        'awaitPromise': awaitPromise,
        'contextId': await contextId,
      },
    );
    final result = getResultOrHandleError(response, evalContents: expression);
    return RemoteObject(result);
  }

  /// Evaluate the JS function with source [jsFunction] in the context of
  /// the library identified by [libraryUri] with [arguments].
  Future<RemoteObject> _evaluateInLibrary(
    String libraryUri,
    String jsFunction,
    List<RemoteObject> arguments,
  ) async {
    final findLibraryJsExpression = globalToolConfiguration
        .loadStrategy
        .dartRuntimeDebugger
        .callLibraryMethodJsExpression(libraryUri, jsFunction);

    final remoteLibrary = await jsEvaluate(findLibraryJsExpression);
    return jsCallFunctionOn(remoteLibrary, jsFunction, arguments);
  }

  /// Evaluates the specified top-level method [methodName] within the library
  /// identified by [libraryUri] using the Dart Development Compiler (DDC)
  /// library bundle strategy with the given optional [arguments].
  Future<RemoteObject> _evaluateLibraryMethodWithDdcLibraryBundle(
    String libraryUri,
    String methodName, [
    List<RemoteObject> arguments = const [],
  ]) {
    final expression = globalToolConfiguration.loadStrategy.dartRuntimeDebugger
        .callLibraryMethodJsExpression(libraryUri, methodName);
    return _jsCallFunction(expression, arguments);
  }

  /// Call [function] with objects referred by [argumentIds] as arguments.
  @override
  Future<RemoteObject> callFunction(
    String function,
    Iterable<String> argumentIds,
  ) {
    final arguments = argumentIds.map(remoteObjectFor).toList();
    return _jsCallFunction(function, arguments);
  }

  @override
  Future<InstanceRef?> instanceRefFor(Object value) =>
      _instanceHelper.instanceRefFor(value);

  Future<Instance?> instanceFor(RemoteObject value) =>
      _instanceHelper.instanceFor(value);

  @override
  Future<LibraryRef?> libraryRefFor(String objectId) =>
      _libraryHelper.libraryRefFor(objectId);

  @override
  Future<Library?> getLibrary(String objectId) async {
    final libraryRef = await libraryRefFor(objectId);
    if (libraryRef == null) return null;
    return _libraryHelper.libraryFor(libraryRef);
  }

  @override
  Future<Obj> getObject(String objectId, {int? offset, int? count}) async {
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
        return _getScript(scriptRef);
      }
      final instance = await _instanceHelper.instanceFor(
        remoteObjectFor(objectId),
        offset: offset,
        count: count,
      );
      if (instance != null) {
        return instance;
      }
    } catch (e, s) {
      _logger.fine('getObject $objectId failed', e, s);
      rethrow;
    }
    throw UnsupportedError(
      'Only libraries, instances, classes, and scripts '
      'are supported for getObject',
    );
  }

  Future<Script> _getScript(ScriptRef scriptRef) async {
    final scriptId = scriptRef.id;
    final scriptUri = scriptRef.uri;
    if (scriptId == null || scriptUri == null) {
      throwInvalidParam('getObject', 'No script info for script $scriptRef');
    }
    final serverPath = DartUri(scriptUri, _root).serverPath;
    final source = await _assetReader.dartSourceContents(serverPath);
    if (source == null) {
      throwInvalidParam(
        'getObject',
        'No source for $scriptRef  with serverPath: $serverPath',
      );
    }
    final libraryId = _scriptIdToLibraryId[scriptId];
    if (libraryId == null) {
      throwInvalidParam('getObject', 'No library for script $scriptRef');
    }
    return Script(
        uri: scriptRef.uri,
        library: await libraryRefFor(libraryId),
        id: scriptId,
      )
      ..tokenPosTable = await _locations.tokenPosTableFor(serverPath)
      ..source = source;
  }

  @override
  Future<MemoryUsage> getMemoryUsage() async {
    final response = await remoteDebugger.sendCommand('Runtime.getHeapUsage');
    final result = response.result;
    if (result == null) {
      throw RPCError(
        'getMemoryUsage',
        RPCErrorKind.kInternalError.code,
        'Null result from chrome Devtools.',
      );
    }
    final jsUsage = HeapUsage(result);
    final usage = MemoryUsage.parse({
      'heapUsage': jsUsage.usedSize,
      'heapCapacity': jsUsage.totalSize,
      'externalUsage': 0,
    });
    if (usage == null) {
      throw RPCError(
        'getMemoryUsage',
        RPCErrorKind.kInternalError.code,
        'Failed to parse memory usage result.',
      );
    }
    return usage;
  }

  /// Returns the [ScriptRef] for the provided Dart server path [uri].
  @override
  Future<ScriptRef?> scriptRefFor(String uri) async {
    await _populateScriptCaches();
    return _serverPathToScriptRef[uri];
  }

  /// Returns the [ScriptRef]s in the library with [libraryId].
  @override
  Future<List<ScriptRef>> scriptRefsForLibrary(String libraryId) async {
    await _populateScriptCaches();
    return _libraryIdToScriptRefs[libraryId] ?? [];
  }

  /// Return the VM SourceReport for the given parameters.
  ///
  /// Currently this implements the 'PossibleBreakpoints' report kind.
  @override
  Future<SourceReport> getSourceReport(
    List<String> reports, {
    String? scriptId,
    int? tokenPos,
    int? endTokenPos,
    bool? forceCompile,
    bool? reportLines,
    List<String>? libraryFilters,
  }) {
    if (reports.contains(SourceReportKind.kCoverage)) {
      throwInvalidParam(
        'getSourceReport',
        'Source report kind ${SourceReportKind.kCoverage} not supported',
      );
    }

    if (reports.isEmpty) {
      throwInvalidParam(
        'getSourceReport',
        'Invalid parameter: no value for source report kind provided.',
      );
    }

    if (reports.length > 1 ||
        reports.first != SourceReportKind.kPossibleBreakpoints) {
      throwInvalidParam('getSourceReport', 'Unsupported source report kind.');
    }

    return _getPossibleBreakpoints(scriptId);
  }

  Future<SourceReport> _getPossibleBreakpoints(String? scriptId) async {
    // TODO(devoncarew): Consider adding some caching for this method.

    final scriptRef = scriptWithId(scriptId);
    if (scriptRef == null) {
      throwInvalidParam('getSourceReport', 'scriptRef not found for $scriptId');
    }
    final scriptUri = scriptRef.uri;
    if (scriptUri == null) {
      throwInvalidParam('getSourceReport', 'scriptUri not found for $scriptId');
    }

    final dartUri = DartUri(scriptUri, _root);
    final mappedLocations = await _locations.locationsForDart(
      dartUri.serverPath,
    );
    // Unlike the Dart VM, the token positions match exactly to the possible
    // breakpoints. This is because the token positions are derived from the
    // DDC source maps which Chrome also uses.
    final tokenPositions = <int>[
      for (final location in mappedLocations) location.tokenPos,
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
    return ScriptList(scripts: await getScriptRefs());
  }

  /// Calls the Chrome Runtime.getProperties API for the object with [objectId].
  ///
  /// Note that the property names are JS names, e.g.
  /// Symbol(DartClass.actualName) and will need to be converted. For a system
  /// List or Map, [offset] and/or [count] can be provided to indicate a desired
  /// range of entries. They will be ignored if there is no [length].
  @override
  Future<List<Property>> getProperties(
    String objectId, {
    int? offset,
    int? count,
    int? length,
  }) async {
    var rangeId = objectId;
    // Ignore offset/count if there is no length:
    if (length != null) {
      if (_isEmptyRange(offset: offset, count: count, length: length)) {
        return [];
      }
      if (_isSubRange(offset: offset, count: count)) {
        final range = await _subRange(
          objectId,
          offset: offset ?? 0,
          count: count,
          length: length,
        );
        rangeId = range.objectId ?? rangeId;
      }
    }
    final jsProperties = await sendCommandAndValidateResult<List>(
      _remoteDebugger,
      method: 'Runtime.getProperties',
      resultField: 'result',
      params: {'objectId': rangeId, 'ownProperties': true},
    );
    return jsProperties
        .map<Property>((each) => Property(each as Map<String, dynamic>))
        .where(_isVisibleProperty)
        .toList();
  }

  bool _isVisibleProperty(Property property) {
    // Filter out any RTI objects from the new DDC type system. See:
    // https://github.com/dart-lang/webdev/issues/2316
    final isRtiObject =
        property.value?.className?.startsWith('dart_rti.Rti') ?? false;
    return !isRtiObject;
  }

  /// Calculate the number of available elements in the range.
  static int _calculateRangeCount({
    int? count,
    required int offset,
    required int length,
  }) => count == null ? length - offset : math.min(count, length - offset);

  /// Find a sub-range of the entries for a Map/List when offset and/or count
  /// have been specified on a getObject request.
  ///
  /// If the object referenced by [id] is not a system List or Map then this
  /// will just return a RemoteObject for it and ignore [offset], [count] and
  /// [length]. If it is, then [length] should be the number of entries in the
  /// List/Map and [offset] and [count] should indicate the desired range.
  Future<RemoteObject> _subRange(
    String id, {
    required int offset,
    required int length,
    int? count,
  }) async {
    // TODO(#809): Sometimes we already know the type of the object, and
    // we could take advantage of that to short-circuit.
    final receiver = remoteObjectFor(id);
    final rangeCount = _calculateRangeCount(
      count: count,
      offset: offset,
      length: length,
    );
    final args =
        [offset, rangeCount].map(dartIdFor).map(remoteObjectFor).toList();
    // If this is a List, just call sublist. If it's a Map, get the entries, but
    // avoid doing a toList on a large map using skip/take to get the section we
    // want. To make those alternatives easier in JS, pass both count and end.
    final expression =
        globalToolConfiguration.loadStrategy.dartRuntimeDebugger
            .getSubRangeJsExpression();

    return await jsCallFunctionOn(receiver, expression, args);
  }

  static bool _isEmptyRange({required int length, int? offset, int? count}) {
    if (count == 0) return true;
    if (offset == null) return false;
    return offset >= length;
  }

  static bool _isSubRange({int? offset, int? count}) {
    if (offset == 0 && count == null) return false;
    return offset != null || count != null;
  }

  /// Returns true for objects we display for the user.
  @override
  bool isDisplayableObject(Object? object) =>
      object is Sentinel ||
      object is InstanceRef &&
          !isNativeJsObject(object) &&
          !isNativeJsError(object);

  /// Returns true for non-dart JavaScript objects.
  bool isNativeJsObject(InstanceRef instanceRef) {
    return _instanceHelper.metadataHelper.isNativeJsObject(
      instanceRef.classRef,
    );
  }

  /// Returns true for JavaScript exceptions.
  @override
  bool isNativeJsError(InstanceRef instanceRef) {
    return _instanceHelper.metadataHelper.isNativeJsError(instanceRef.classRef);
  }

  /// Request and cache `<ScriptRef>`s for all the scripts in the application.
  ///
  /// This populates [_scriptRefsById], [_scriptIdToLibraryId],
  /// [_libraryIdToScriptRefs] and [_serverPathToScriptRef].
  ///
  /// This will get repopulated on restarts and reloads.
  ///
  /// If [modifiedModuleReport] is provided, only invalidates and
  /// recalculates caches for the modified libraries.
  ///
  /// Returns the list of scripts refs cached.
  Future<List<ScriptRef>> _populateScriptCaches({
    ModifiedModuleReport? modifiedModuleReport,
  }) {
    return _scriptCacheMemoizer.runOnce(() async {
      final scripts =
          await globalToolConfiguration.loadStrategy
              .metadataProviderFor(appConnection.request.entrypointPath)
              .scripts;
      if (modifiedModuleReport != null) {
        // Invalidate any script caches that were computed for the now invalid
        // libraries. They will get repopulated below.
        for (final libraryUri in modifiedModuleReport.modifiedLibraries) {
          final libraryRef = await _libraryHelper.libraryRefFor(libraryUri);
          final libraryId = libraryRef?.id;
          // If this was not a pre-existing library, nothing to invalidate.
          if (libraryId == null) continue;
          final scriptRefs = _libraryIdToScriptRefs.remove(libraryId);
          if (scriptRefs == null) continue;
          for (final scriptRef in scriptRefs) {
            final scriptId = scriptRef.id;
            final scriptUri = scriptRef.uri;
            if (scriptId != null && scriptUri != null) {
              _scriptRefsById.remove(scriptId);
              _scriptIdToLibraryId.remove(scriptId);
              _serverPathToScriptRef.remove(
                DartUri(scriptUri, _root).serverPath,
              );
            }
          }
        }
      }
      // For all the non-dart: libraries, find their parts and create scriptRefs
      // for them.
      final userLibraries = _userLibraryUris(
        isolate.libraries ?? <LibraryRef>[],
      );
      for (final uri in userLibraries) {
        if (modifiedModuleReport?.modifiedLibraries.contains(uri) == false) {
          continue;
        }
        final parts = scripts[uri];
        final scriptRefs = [
          ScriptRef(uri: uri, id: createId()),
          for (final part in parts ?? []) ScriptRef(uri: part, id: createId()),
        ];
        final libraryRef = await _libraryHelper.libraryRefFor(uri);
        final libraryId = libraryRef?.id;
        if (libraryId != null) {
          final libraryIdToScriptRefs = _libraryIdToScriptRefs.putIfAbsent(
            libraryId,
            () => <ScriptRef>[],
          );
          for (final scriptRef in scriptRefs) {
            final scriptId = scriptRef.id;
            final scriptUri = scriptRef.uri;
            if (scriptId != null && scriptUri != null) {
              _scriptRefsById[scriptId] = scriptRef;
              _scriptIdToLibraryId[scriptId] = libraryId;
              _serverPathToScriptRef[DartUri(scriptUri, _root).serverPath] =
                  scriptRef;
              libraryIdToScriptRefs.add(scriptRef);
            }
          }
        }
      }
      return _scriptRefsById.values.toList();
    });
  }

  Iterable<String> _userLibraryUris(Iterable<LibraryRef> libraries) {
    return libraries
        .map((library) => library.uri ?? '')
        .where((uri) => uri.isNotEmpty && !uri.startsWith('dart:'));
  }

  /// Look up the script by id in an isolate.
  @override
  ScriptRef? scriptWithId(String? scriptId) =>
      scriptId == null ? null : _scriptRefsById[scriptId];

  /// Runs an eval on the page to compute all existing registered extensions.
  ///
  /// Combines this with the RPCs registered in the [isolate]. Use this over
  /// [Isolate.extensionRPCs] as this computes a live set.
  ///
  /// Updates [Isolate.extensionRPCs] to this set.
  Future<Set<String>> getExtensionRpcs() async {
    final expression =
        globalToolConfiguration.loadStrategy.dartRuntimeDebugger
            .getDartDeveloperExtensionNamesJsExpression();
    final extensionRpcs = <String>{};
    final params = {
      'expression': expression,
      'returnByValue': true,
      'contextId': await contextId,
    };
    try {
      final response = await remoteDebugger.sendCommand(
        'Runtime.evaluate',
        params: params,
      );
      final result = getResultOrHandleError(response, evalContents: expression);
      extensionRpcs.addAll(List.from(result['value'] as List? ?? []));
    } catch (e, s) {
      _logger.severe(
        'Error calling Runtime.evaluate with params $params',
        e,
        s,
      );
    }
    isolate.extensionRPCs = List<String>.of(extensionRpcs);
    return extensionRpcs;
  }

  /// Convert a JS exception description into a description containing
  /// a Dart stack trace.
  @override
  Future<String> mapExceptionStackTrace(String description) async {
    RemoteObject mapperResult;
    try {
      mapperResult = await _jsCallFunction(stackTraceMapperExpression, <Object>[
        description,
      ]);
    } catch (_) {
      return description;
    }
    final mappedStack = mapperResult.value?.toString();
    if (mappedStack == null || mappedStack.isEmpty) {
      return description;
    }
    final message = _allLinesBeforeStackTrace(description);
    return '$message$mappedStack';
  }

  String _allLinesBeforeStackTrace(String description) {
    var message = '';
    for (final match in exceptionMessageRegex.allMatches(description)) {
      final isStackTraceLine = stackTraceLineRegex.hasMatch(match[0] ?? '');
      if (isStackTraceLine) break;
      message += '${match[0]}\n';
    }
    return message;
  }
}
