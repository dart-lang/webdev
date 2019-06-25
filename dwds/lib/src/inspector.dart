// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';
import 'debugger.dart';
import 'helpers.dart';

/// An inspector for a running Dart application contained in the
/// [WipConnection].
///
/// Provides information about currently loaded scripts and objects and support
/// for eval.
class AppInspector {
  /// Map of class ID to [Class].
  final _classes = <String, Class>{};

  /// Map of scriptRef ID to [ScriptRef].
  final _scriptRefs = <String, ScriptRef>{};

  /// Map of Dart server path to [ScriptRef].
  final _serverPathToScriptRef = <String, ScriptRef>{};

  /// Map of library ID to [Library].
  final _libraries = <String, Library>{};

  /// Map of libraryRef ID to [LibraryRef].
  final _libraryRefs = <String, LibraryRef>{};

  /// Map of [ScriptRef] id to containing [LibraryRef] id.
  final _scriptIdToLibraryId = <String, String>{};

  final WipConnection _tabConnection;
  final AssetHandler _assetHandler;
  final Debugger _debugger;
  final Isolate isolate;
  final IsolateRef isolateRef;

  /// The root URI from which the application is served.
  final String _root;

  AppInspector._(
    this.isolate,
    this._tabConnection,
    this._assetHandler,
    this._debugger,
    this._root,
  ) : isolateRef = _toIsolateRef(isolate);

  Future<void> _initialize() async {
    isolate.libraries.addAll(await _getLibraryRefs());

    // TODO: Something more robust here, right now we rely on the 2nd to last
    // library being the root one (the last library is the bootstrap lib).
    isolate.rootLib = isolate.libraries[isolate.libraries.length - 2];

    isolate.extensionRPCs.addAll(await _getExtensionRpcs());

    isolate.pauseEvent = Event()
      ..kind = EventKind.kResume
      ..isolate = isolateRef;
  }

  static IsolateRef _toIsolateRef(Isolate isolate) => IsolateRef()
    ..id = isolate.id
    ..name = isolate.name
    ..number = isolate.number;

  static Future<AppInspector> initialize(
  WipConnection tabConnection,
    AssetHandler assetHandler,
    Debugger debugger,
    String root,
  ) async {
    var id = createId();
    var isolate = Isolate()
      ..id = id
      ..number = id
      ..name = '$root:main()'
      ..runnable = true
      ..breakpoints = []
      ..libraries = []
      ..extensionRPCs = [];
    var inspector =
        AppInspector._(isolate, tabConnection, assetHandler, debugger, root);
    await inspector._initialize();
    return inspector;
  }

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
      result = await _tabConnection.runtime.sendCommand('Runtime.evaluate',
          params: {'expression': evalExpression});
      handleErrorIfPresent(result,
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
      result = await _tabConnection.runtime
          .sendCommand('Runtime.callFunctionOn', params: {
        'functionDeclaration': evalExpression,
        'arguments': arguments,
        // TODO(jakemac): Use the executionContext instead, or possibly the
        // library object. This will get weird if people try to use `this` in
        // their expression.
        'objectId': scope.values.first,
      });
      handleErrorIfPresent(result,
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
    var scriptRef = _scriptRefs[objectId];
    if (scriptRef != null) return await _getScript(isolateId, scriptRef);

    throw UnsupportedError(
        'Only libraries and classes are supported for getObject');
  }

  Future<Library> _constructLibrary(LibraryRef libraryRef) async {
    // Fetch information about all the classes in this library.
    var expression = '''
    (function() {
      ${_getLibrarySnippet(libraryRef.uri)}
      var parts = sdkUtils.getParts('${libraryRef.uri}');
      var result = {'parts' : parts}
      var classes = Object.values(library)
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
          descriptor['fields'][name] = {
            // TODO(jakemac): how can we get actual const info?
            "isConst": false,
            "isFinal": field.isFinal,
            "isStatic": false,
          }
        }

        return descriptor;
      });
      result['classes'] = classList;
      return result;
    })()
    ''';
    var result = await _tabConnection.runtime.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(result, evalContents: expression);
    var classDescriptors = (result.result['result']['value']['classes'] as List)
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
          ..declaredType = (InstanceRef()..classRef = ClassRef())
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

    // Parts are relative paths from the libraryRef uri.
    var parts =
        (result.result['result']['value']['parts'] as List).cast<String>();
    // Note that uris here are scheme based
    // e.g. org-dartlang-app:///web/main.dart
    // We will need to normalize the parent if dart-lang/sdk#37336 ever gets
    // fixed.
    var parent = libraryRef.uri.substring(0, libraryRef.uri.lastIndexOf('/'));
    var scriptRefs = [
      ScriptRef()
        ..uri = libraryRef.uri
        ..id = createId(),
      for (var part in parts)
        ScriptRef()
          ..uri = p.join(parent, part)
          ..id = createId()
    ];

    for (var scriptRef in scriptRefs) {
      _scriptRefs[scriptRef.id] = scriptRef;
      _scriptIdToLibraryId[scriptRef.id] = libraryRef.id;
      _serverPathToScriptRef[DartUri(scriptRef.uri, _root).serverPath] =
          scriptRef;
    }

    return Library()
      ..id = libraryRef.id
      ..name = libraryRef.name
      ..uri = libraryRef.uri
      ..classes = classRefs
      ..debuggable = true
      ..dependencies = []
      ..functions = []
      ..scripts = scriptRefs
      ..variables = [];
  }

  Future<Script> _getScript(String isolateId, ScriptRef scriptRef) async {
    var libraryId = _scriptIdToLibraryId[scriptRef.id];
    var serverPath = DartUri(scriptRef.uri, _root).serverPath;
    var script = await _assetHandler(serverPath);
    return Script()
      ..library = _libraryRefs[libraryId]
      ..id = scriptRef.id
      ..uri = scriptRef.uri
      ..tokenPosTable = _debugger.sources.tokenPosTableFor(serverPath)
      ..source = script;
  }

  /// Returns the [ScriptRef] for the provided Dart server path [uri].
  ScriptRef scriptRefFor(String uri) => _serverPathToScriptRef[uri];

  Future<ScriptList> getScripts(String isolateId) async {
    var scripts = await scriptRefs(isolateId);
    return ScriptList()..scripts = scripts;
  }

  /// Returns all scripts in the isolate.
  Future<List<ScriptRef>> scriptRefs(String isolateId) async {
    if (isolateId != isolate.id) {
      throw ArgumentError.value(
          isolateId, 'isolateId', 'Unrecognized isolate id');
    }
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

  /// Look up the script by id in an isolate.
  Future<ScriptRef> scriptWithId(String scriptId) async =>
      (await scriptRefs(isolate.id)).firstWhere((ref) => ref.id == scriptId);

  /// Returns all libraryRefs in the app.
  ///
  /// Note this can return a cached result.
  Future<List<LibraryRef>> _getLibraryRefs() async {
    if (_libraryRefs.isNotEmpty) return _libraryRefs.values.toList();
    var expression = "require('dart_sdk').dart.getLibraries();";
    var librariesResult = await _tabConnection.runtime.sendCommand(
        'Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(librariesResult, evalContents: expression);
    var libraries =
        List<String>.from(librariesResult.result['result']['value'] as List);
    for (var library in libraries) {
      var ref = LibraryRef()
        ..id = library
        ..name = library
        ..uri = library;
      _libraryRefs[ref.id] = ref;
    }
    return _libraryRefs.values.toList();
  }

  /// Runs an eval on the page to compute all existing registered extensions.
  Future<List<String>> _getExtensionRpcs() async {
    var expression = "require('dart_sdk').developer._extensions.keys.toList();";
    var extensionsResult = await _tabConnection.runtime.sendCommand(
        'Runtime.evaluate',
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
  var libraryName = '$libraryUri';
  var sdkUtils = require('dart_sdk').dart;
  var moduleName = sdkUtils.getModuleNames().find(
    (name) => sdkUtils.getModuleLibraries(name)[libraryName]);
  var library = sdkUtils.getModuleLibraries(moduleName)[libraryName];
  if (!library) throw 'cannot find library for ' + libraryName + ' under ' + moduleName;
''';

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
