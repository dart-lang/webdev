// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:path/path.dart' as p;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../asset_handler.dart';
import '../services/chrome_proxy_service.dart';
import '../utilities/conversions.dart';
import '../utilities/dart_uri.dart';
import '../utilities/domain.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'debugger.dart';
import 'exceptions.dart';
import 'instance.dart';
import 'metadata.dart';

/// An inspector for a running Dart application contained in the
/// [WipConnection].
///
/// Provides information about currently loaded scripts and objects and support
/// for eval.
class AppInspector extends Domain {
  /// Map of class ID to [Class].
  final _classes = <String, Class>{};

  Future<List<ScriptRef>> _cachedScriptRefs;

  Future<List<ScriptRef>> get _scriptRefs =>
      _cachedScriptRefs ??= _getScripts();

  /// Map of scriptRef ID to [ScriptRef].
  final _scriptRefsById = <String, ScriptRef>{};

  /// Map of Dart server path to [ScriptRef].
  final _serverPathToScriptRef = <String, ScriptRef>{};

  /// Map of library ID to [Library].
  final _libraries = <String, Library>{};

  /// Map of libraryRef ID to [LibraryRef].
  final _libraryRefs = <String, LibraryRef>{};

  /// Map of [ScriptRef] id to containing [LibraryRef] id.
  final _scriptIdToLibraryId = <String, String>{};

  final RemoteDebugger _remoteDebugger;
  final AssetHandler _assetHandler;
  final Debugger debugger;
  final Isolate isolate;
  final IsolateRef isolateRef;
  final InstanceHelper instanceHelper;
  final AppConnection appConnection;

  /// The root URI from which the application is served.
  final String _root;

  AppInspector._(
    this.appConnection,
    this.isolate,
    this._assetHandler,
    this.debugger,
    this._root,
    this._remoteDebugger,
    this.instanceHelper,
  )   : isolateRef = _toIsolateRef(isolate),
        super.forInspector();

  @override

  /// We are the inspector, so this getter is trivial.
  AppInspector get inspector => this;

  Future<void> _initialize() async {
    var libraries = await _getLibraryRefs();
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
      Debugger debugger,
      String root,
      InstanceHelper instanceHelper) async {
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
    debugger.notifyPausedAtStart();
    var inspector = AppInspector._(
      appConnection,
      isolate,
      assetHandler,
      debugger,
      root,
      remoteDebugger,
      instanceHelper,
    );
    await inspector._initialize();
    return inspector;
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
        await _remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
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
  ${_getLibrarySnippet(libraryUri)};
  return library.$expression;
})();
''';
    return jsEvaluate(evalExpression);
  }

  /// Evaluate [expression] by calling Chrome's Runtime.evaluate.
  Future<RemoteObject> jsEvaluate(String expression) async {
    // TODO(alanknight): Support a version with arguments if needed.
    WipResponse result;
    result = await _remoteDebugger
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
  ${_getLibrarySnippet(library.uri)};
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
  ${_getLibrarySnippet(library.uri)};
  return library.$expression;
}
    ''';
    return _evaluateInLibrary(library, evalExpression, arguments);
  }

  Future<Library> _getLibrary(String isolateId, String objectId) async {
    if (isolateId != isolate.id) return null;
    var libraryRef = _libraryRefs[objectId];
    if (libraryRef == null) return null;
    var library = _libraries[objectId];
    if (library != null) return library;
    library = await _constructLibrary(libraryRef);
    _libraries[objectId] = library;
    return library;
  }

  Future getObject(String isolateId, String objectId,
      {int offset, int count}) async {
    var library = await _getLibrary(isolateId, objectId);
    if (library != null) return library;
    var clazz = _classes[objectId];
    if (clazz != null) return clazz;
    var scriptRef = _scriptRefsById[objectId];
    if (scriptRef != null) return await _getScript(isolateId, scriptRef);
    var instance =
        instanceHelper.instanceFor(RemoteObject({'objectId': objectId}));
    if (instance != null) return instance;
    throw UnsupportedError('Only libraries, instances, classes, and scripts '
        'are supported for getObject');
  }

  Future<Library> _constructLibrary(LibraryRef libraryRef) async {
    // Fetch information about all the classes in this library.
    var expression = '''
    (function() {
      ${_getLibrarySnippet(libraryRef.uri)}
      var result = {};
      var classes = Object.values(Object.getOwnPropertyDescriptors(library))
        .filter((p) => 'value' in p)
        .map((p) => p.value)
        .filter((l) => l && sdkUtils.isType(l));
      var classList = classes.map(function(clazz) {
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
          var libraryUri = Object.getOwnPropertySymbols(fields[name]["type"])
          .find(x => x.description == "libraryUri");
          descriptor['fields'][name] = {
            // TODO(jakemac): how can we get actual const info?
            "isConst": false,
            "isFinal": field.isFinal,
            "isStatic": false,
            "classRefName": fields[name]["type"]["name"],
            "classRefLibraryId" : field["type"][libraryUri],
          }
        }

        return descriptor;
      });
      result['classes'] = classList;
      return result;
    })()
    ''';
    var result = await _remoteDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(result, evalContents: expression);
    var classDescriptors = (result.result['result']['value']['classes'] as List)
        .cast<Map<String, Object>>();
    var classRefs = <ClassRef>[];
    for (var classDescriptor in classDescriptors) {
      var classMetaData =
          ClassMetaData(classDescriptor['name'] as String, libraryRef.id);
      var classRef = ClassRef(name: classMetaData.name, id: classMetaData.id);
      classRefs.add(classRef);

      var methodRefs = <FuncRef>[];
      var methodDescriptors =
          classDescriptor['methods'] as Map<String, dynamic>;
      methodDescriptors.forEach((name, descriptor) {
        var methodId = '${classMetaData.id}:$name';
        methodRefs.add(FuncRef(
            id: methodId,
            name: name,
            owner: classRef,
            isConst: descriptor['isConst'] as bool,
            isStatic: descriptor['isStatic'] as bool));
      });

      var fieldRefs = <FieldRef>[];
      var fieldDescriptors = classDescriptor['fields'] as Map<String, dynamic>;
      fieldDescriptors.forEach((name, descriptor) async {
        var classMetaData = ClassMetaData(
          descriptor['classRefName'] as String,
          descriptor['classRefLibraryId'] as String,
        );
        fieldRefs.add(FieldRef(
            name: name,
            owner: classRef,
            declaredType: InstanceRef(
                id: createId(),
                kind: InstanceKind.kType,
                classRef:
                    ClassRef(name: classMetaData.name, id: classMetaData.id)),
            isConst: descriptor['isConst'] as bool,
            isFinal: descriptor['isFinal'] as bool,
            isStatic: descriptor['isStatic'] as bool,
            id: createId()));
      });

      // TODO: Implement the rest of these
      // https://github.com/dart-lang/webdev/issues/176.
      _classes[classMetaData.id] = Class(
          name: classMetaData.name,
          isAbstract: false,
          isConst: false,
          library: libraryRef,
          interfaces: [],
          fields: fieldRefs,
          functions: methodRefs,
          subclasses: [],
          id: classMetaData.id);
    }
    return Library(
        name: libraryRef.name,
        uri: libraryRef.uri,
        debuggable: true,
        dependencies: [],
        scripts: await _scriptRefs,
        variables: [],
        functions: [],
        classes: classRefs,
        id: libraryRef.id);
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
      library: _libraryRefs[libraryId],
      id: scriptRef.id,
    )
      ..tokenPosTable = await debugger.tokenPosTableFor(serverPath)
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
    return ScriptList()..scripts = await _scriptRefs;
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
    var result = await _remoteDebugger.sendCommand('Runtime.evaluate',
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
      var libraryRef = _libraryRefs[uri];
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

  /// Returns all libraryRefs in the app.
  ///
  /// Note this can return a cached result.
  Future<List<LibraryRef>> _getLibraryRefs() async {
    if (_libraryRefs.isNotEmpty) return _libraryRefs.values.toList();
    var expression = '''
      (function() {
        $getLibraries
        return libs;
      })()
     ''';
    var librariesResult = await _remoteDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(librariesResult, evalContents: expression);
    var libraries =
        List<String>.from(librariesResult.result['result']['value'] as List);
    // Filter out any non-Dart libraries, which basically means the .bootstrap
    // library from build_web_runners.
    var dartLibraries = libraries
        .where((name) => name.startsWith('dart:') || name.endsWith('.dart'));
    for (var library in dartLibraries) {
      var ref = LibraryRef(id: library, name: library, uri: library);
      _libraryRefs[ref.id] = ref;
    }
    return _libraryRefs.values.toList();
  }

  /// Runs an eval on the page to compute all existing registered extensions.
  Future<List<String>> _getExtensionRpcs() async {
    var expression =
        "$loadModule('dart_sdk').developer._extensions.keys.toList();";
    var extensionsResult = await _remoteDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(extensionsResult, evalContents: expression);
    return List.from(extensionsResult.result['result']['value'] as List);
  }
}

/// Creates a snippet of JS code that initializes a `library` variable that has
/// the actual library object in DDC for [libraryUri].
///
/// In DDC we have module libraries indexed by names of the form
/// 'packages/package/mainFile' with no .dart suffix on the file, or
/// 'directory/packageName/mainFile', also with no .dart suffix, and relative to
/// the serving root, normally /web within the package. These modules have a map
/// from the URI with a Dart-specific scheme (package: or org-dartlang-app:) to
/// the library objects. The [libraryUri] parameter should be one of these
/// Dart-specific scheme URIs, and we set `library` the corresponding library.
String _getLibrarySnippet(String libraryUri) => '''
   var sdkUtils = $loadModule('dart_sdk').dart;
   var library = sdkUtils.getLibrary('$libraryUri');
   if (!library) throw 'cannot find library for $libraryUri';
  ''';
