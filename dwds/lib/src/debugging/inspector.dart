// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/src/debugging/debugger.dart';
import 'package:path/path.dart' as p;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../asset_handler.dart';
import '../connections/app_connection.dart';
import '../debugging/location.dart';
import '../debugging/remote_debugger.dart';
import '../utilities/conversions.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'classes.dart';
import 'exceptions.dart';
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

  final LibraryHelper libraryHelper;
  final ClassHelper classHelper;
  final InstanceHelper instanceHelper;

  final AssetHandler _assetHandler;
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
    this._assetHandler,
    this._locations,
    this._root,
  )   : isolateRef = _toIsolateRef(isolate),
        super.forInspector();

  @override

  /// We are the inspector, so this getter is trivial.
  AppInspector get inspector => this;

  Future<void> _initialize() async {
    var libraries = await libraryHelper.libraryRefs;
    isolate.libraries.addAll(libraries);
    await DartUri.recordAbsoluteUris(libraries.map((lib) => lib.uri));

    // TODO: Something more robust here, right now we rely on the 2nd to last
    // library being the root one (the last library is the bootstrap lib).
    isolate.rootLib = isolate.libraries[isolate.libraries.length - 1];

    isolate.extensionRPCs.addAll(await _getExtensionRpcs());
  }

  static IsolateRef _toIsolateRef(Isolate isolate) =>
      IsolateRef(id: isolate.id, name: isolate.name, number: isolate.number);

  static Future<AppInspector> initialize(
    AppConnection appConnection,
    RemoteDebugger remoteDebugger,
    AssetHandler assetHandler,
    Locations locations,
    String root,
    Debugger debugger,
  ) async {
    var id = createId();
    var time = DateTime.now().millisecondsSinceEpoch;
    var name = '$root:main()';
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
            isolate: IsolateRef(id: id, name: name, number: id)),
        livePorts: 0,
        libraries: [],
        breakpoints: [],
        exceptionPauseMode: debugger.pauseState)
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
      assetHandler,
      locations,
      root,
    );
    await appInspector._initialize();
    return appInspector;
  }

  /// Get the value of the field named [fieldName] from [receiver].
  Future<RemoteObject> loadField(RemoteObject receiver, String fieldName) {
    var load = '''
        function() {
          return $loadModule("dart_sdk").dart.dloadRepl(this, "$fieldName");
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
          return $loadModule("dart_sdk").dart.dsendRepl(this, "$methodName", arguments);
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
      {Map<String, String> scope, bool disableBreakpoints}) async {
    scope ??= {};
    disableBreakpoints ??= false;
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
    checkIsolate(isolateId);
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
  ${getLibrarySnippet(libraryUri)};
  return library.$expression;
})();
''';
    return jsEvaluate(evalExpression);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluate.
  Future<RemoteObject> jsEvaluate(String expression) async {
    // TODO(alanknight): Support a version with arguments if needed.
    WipResponse result;
    result = await remoteDebugger
        .sendCommand('Runtime.evaluate', params: {'expression': expression});
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
  ${getLibrarySnippet(library.uri)};
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
  ${getLibrarySnippet(library.uri)};
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

  Future getObject(String isolateId, String objectId,
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
    var response = await _assetHandler.getRelativeAsset(serverPath);
    if (response.statusCode != HttpStatus.ok) {
      throw ScriptNotFound(serverPath, response);
    }
    var script = await response.readAsString();
    return Script(
        uri: scriptRef.uri,
        library: await libraryHelper.libraryRefFor(libraryId),
        id: scriptRef.id)
      ..tokenPosTable = await _locations.tokenPosTableFor(serverPath)
      ..source = script;
  }

  /// Returns the [ScriptRef] for the provided Dart server path [uri].
  Future<ScriptRef> scriptRefFor(String uri) async {
    if (_serverPathToScriptRef.isEmpty) {
      // TODO(grouma) - populate the server path cache a better way.
      await getScripts(isolate.id);
    }
    return _serverPathToScriptRef[uri];
  }

  /// All the scripts in the isolate.
  Future<ScriptList> getScripts(String isolateId) async {
    checkIsolate(isolateId);
    return ScriptList()..scripts = await scriptRefs;
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
    // We can't pass parameters to an eval, so encode the list and inline it in
    // the expression.
    var listAsJson = jsonEncode(libraryUris);
    var expression = '''
    (function() {
      var uris = JSON.parse('$listAsJson');
      var allScripts = {};
      var sdkUtils = $loadModule('dart_sdk').dart;
      for (var uri of uris) {
        var parts = sdkUtils.getParts(uri);
        allScripts[uri] = parts;
      }
      return allScripts;
    })()
    ''';
    var result = await remoteDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(result, evalContents: expression);
    var allScripts = result.result['result']['value'];

    // For all the non-dart: libraries, find their parts and create scriptRefs
    // for them.
    var userLibraries = libraryUris.where((uri) => !uri.startsWith('dart:'));
    for (var uri in userLibraries) {
      var parent = uri.substring(0, uri.lastIndexOf('/'));
      var parts = (allScripts[uri] as List).cast<String>();
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
  Future<ScriptRef> scriptWithId(String scriptId) async =>
      _scriptRefsById[scriptId];

  /// Runs an eval on the page to compute all existing registered extensions.
  Future<List<String>> _getExtensionRpcs() async {
    var expression =
        "$loadModule('dart_sdk').developer._extensions.keys.toList();";
    var extensionsResult = await remoteDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(extensionsResult, evalContents: expression);
    return List.from(extensionsResult.result['result']['value'] as List);
  }
}
