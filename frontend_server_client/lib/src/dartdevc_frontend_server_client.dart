// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'frontend_server_client.dart';
import 'shared.dart';

/// Wraps a [FrontendServerClient] with opinionated web specific functionality,
/// and provides some typical defaults.
///
/// Loads into memory the [CompileResult]s from each [compile] call, and
/// provides access to the up to date sources and source maps.
///
/// Also has the ability to create a bootstrap file for the current entrypoint.
class DartDevcFrontendServerClient implements FrontendServerClient {
  final FrontendServerClient _frontendServerClient;

  final _assets = <String, Uint8List>{};

  DartDevcFrontendServerClient._(this._frontendServerClient);

  static Future<DartDevcFrontendServerClient> start(
    String entrypoint,
    String outputDillPath, {
    bool debug = false,
    bool enableHttpUris = false,
    List<String> fileSystemRoots = const [], // For `fileSystemScheme` uris,
    String fileSystemScheme =
        'org-dartlang-root', // Custom scheme for virtual `fileSystemRoots`.
    String packagesJson = '.dart_tool/package_config.json',
    String platformKernel, // Defaults to the dartdevc platfrom from the sdk.
    String sdkRoot, // Defaults to the current SDK root.
  }) async {
    var feServer = await FrontendServerClient.start(
      entrypoint,
      outputDillPath,
      platformKernel ?? _dartdevcPlatformKernel,
      debug: debug,
      enableHttpUris: enableHttpUris,
      fileSystemRoots: fileSystemRoots,
      fileSystemScheme: fileSystemScheme,
      packagesJson: packagesJson,
      sdkRoot: sdkRoot,
      target: 'dartdevc',
    );
    return DartDevcFrontendServerClient._(feServer);
  }

  /// Returns the current bytes for the asset at [path].
  ///
  /// The [path] should be exactly as it appears in the
  /// [CompileResult.jsManifestOutput] file.
  ///
  /// Returns `null` if no asset exists at [path].
  Uint8List assetBytes(String path) => _assets[path];

  /// The contents of a JS file capable of bootstrapping the current app.
  ///
  /// TODO: implement
  String bootstrapJs() => throw UnimplementedError();

  /// Updates [_assets] for [result].
  Future<void> _updateAssets(CompileResult result) async {
    Map<String, dynamic> manifest;
    Uint8List sourceBytes;
    Uint8List sourceMapBytes;
    await Future.wait([
      File(result.jsManifestOutput)
          .readAsString()
          .then((json) => manifest = jsonDecode(json) as Map<String, dynamic>),
      File(result.jsSourcesOutput)
          .readAsBytes()
          .then((bytes) => sourceBytes = bytes),
      File(result.jsSourceMapsOutput)
          .readAsBytes()
          .then((bytes) => sourceMapBytes = bytes),
    ]);

    for (var entry in manifest.entries) {
      var metadata = entry.value as Map<String, dynamic>;
      var sourceOffsets = metadata['code'] as List;
      _assets[entry.key] =
          sourceBytes.sublist(sourceOffsets[0] as int, sourceOffsets[1] as int);
      var sourceMapOffsets = metadata['sourcemap'] as List;
      _assets['${entry.key}.map'] = sourceMapBytes.sublist(
          sourceMapOffsets[0] as int, sourceMapOffsets[1] as int);
    }
  }

  @override
  Future<CompileResult> compile([List<Uri> invalidatedUris]) async {
    var result = await _frontendServerClient.compile(invalidatedUris);
    await _updateAssets(result);
    return result;
  }

  @override
  Future<CompileResult> compileExpression({
    @required String expression,
    @required List<String> definitions,
    @required bool isStatic,
    @required String klass,
    @required String libraryUri,
    @required List<String> typeDefinitions,
  }) =>
      throw UnsupportedError(
          'Use `compileExpressionToJs` for dartdevc based clients');

  @override
  Future<CompileResult> compileExpressionToJs({
    @required String expression,
    @required int column,
    @required Map<String, String> jsFrameValues,
    @required Map<String, String> jsModules,
    @required String libraryUri,
    @required int line,
    @required String moduleName,
  }) =>
      _frontendServerClient.compileExpressionToJs(
          expression: expression,
          column: column,
          jsFrameValues: jsFrameValues,
          jsModules: jsModules,
          libraryUri: libraryUri,
          line: line,
          moduleName: moduleName);

  @override
  void accept() => _frontendServerClient.accept();

  @override
  void reject() {
    _frontendServerClient.reject();
    _assets.clear();
  }

  @override
  void reset() {
    _frontendServerClient.reset();
    _assets.clear();
  }

  @override
  bool kill({ProcessSignal processSignal = ProcessSignal.sigterm}) =>
      _frontendServerClient.kill();

  @override
  Future<int> shutdown() => _frontendServerClient.shutdown();
}

final _dartdevcPlatformKernel =
    p.join(sdkDir, 'lib', '_internal', 'ddc_sdk.dill');
