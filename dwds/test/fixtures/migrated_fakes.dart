// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:dwds/asset_reader.dart';
import 'package:dwds/src/debugging/classes.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/libraries.dart';
import 'package:vm_service/vm_service.dart';


class FakeStrategy implements LoadStrategy {
  @override
  Future<String> bootstrapFor(String entrypoint) async => 'dummy_bootstrap';

  @override
  shelf.Handler get handler =>
      (request) => (request.url.path == 'someDummyPath')
          ? shelf.Response.ok('some dummy response')
          : shelf.Response.notFound('someDummyPath');

  @override
  String get id => 'dummy-id';

  @override
  String get moduleFormat => 'dummy-format';

  @override
  String get loadLibrariesModule => '';

  @override
  String get loadLibrariesSnippet => '';

  @override
  String loadLibrarySnippet(String libraryUri) => '';

  @override
  String get loadModuleSnippet => '';

  @override
  ReloadConfiguration get reloadConfiguration => ReloadConfiguration.none;

  @override
  String loadClientSnippet(String clientScript) => 'dummy-load-client-snippet';

  @override
  Future<String> moduleForServerPath(String entrypoint, String serverPath) =>
      Future.value('');

  @override
  Future<String> serverPathForModule(String entrypoint, String module) =>
      Future.value('');

  @override
  Future<String> sourceMapPathForModule(String entrypoint, String module) =>
      Future.value('');

  @override
  String serverPathForAppUri(String appUri) => '';

  @override
  MetadataProvider metadataProviderFor(String entrypoint) =>
      MetadataProvider(entrypoint, FakeAssetReader());

  @override
  void trackEntrypoint(String entrypoint) {}

  @override
  Future<Map<String, ModuleInfo>> moduleInfoForEntrypoint(String entrypoint) =>
      throw UnimplementedError();
}

class FakeAssetReader implements AssetReader {
  final String? _metadata;
  final String? _dartSource;
  final String? _sourceMap;
  FakeAssetReader({
    metadata,
    dartSource,
    sourceMap,
  })  : _metadata = metadata,
        _dartSource = dartSource,
        _sourceMap = sourceMap;

  @override
  Future<String> dartSourceContents(String serverPath) {
    return _throwUnimplementedOrReturnContents(_dartSource);
  }

  @override
  Future<String> metadataContents(String serverPath) {
    return _throwUnimplementedOrReturnContents(_metadata);
  }

  @override
  Future<String> sourceMapContents(String serverPath) {
    return _throwUnimplementedOrReturnContents(_sourceMap);
  }

  @override
  Future<void> close() async {}

  Future<String> _throwUnimplementedOrReturnContents(String? contents) {
    if (contents == null) throw UnimplementedError();
    return Future.value(contents);
  }
}

/// Constructs a trivial Isolate we can use when we need to provide one but
/// don't want go through initialization.
Isolate get simpleIsolate => Isolate(
      id: '1',
      number: '1',
      name: 'fake',
      libraries: [],
      exceptionPauseMode: 'abc',
      breakpoints: [],
      pauseOnExit: false,
      pauseEvent: null,
      startTime: 0,
      livePorts: 0,
      runnable: false,
      isSystemIsolate: false,
      isolateFlags: [],
    );

class FakeInspector implements AppInspector {
  FakeInspector({required this.fakeIsolate});

  Isolate fakeIsolate;


  @override
  Object noSuchMethod(Invocation invocation) {
    throw UnsupportedError('This is a fake');
  }

  @override
  Future<void> initialize(LibraryHelper libraryHelper, ClassHelper classHelper,
          InstanceHelper instanceHelper) =>
      Future.value(null);

  @override
  Future<InstanceRef?> instanceRefFor(Object value) =>
      Future.value(InstanceHelper.kNullInstanceRef);

  @override
  Future<Obj> getObject(String objectId, {int? offset, int? count}) =>
      Future.value(Obj.parse({}));

  @override
  Future<ScriptList> getScripts() => Future.value(ScriptList(scripts: []));

  @override
  Future<ScriptRef> scriptRefFor(String uri) =>
      Future.value(ScriptRef(id: 'fake', uri: 'fake://uri'));

  @override
  ScriptRef? scriptWithId(String? scriptId) => null;

  @override
  Isolate get isolate => fakeIsolate;

  @override
  IsolateRef get isolateRef => IsolateRef(
        id: fakeIsolate.id,
        number: fakeIsolate.number,
        name: fakeIsolate.name,
        isSystemIsolate: fakeIsolate.isSystemIsolate,
      );
}
