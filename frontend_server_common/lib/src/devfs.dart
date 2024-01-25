// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'package:dwds/asset_reader.dart';
import 'package:dwds/config.dart';
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/utilities.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:test_common/test_sdk_layout.dart';

import 'asset_server.dart';
import 'bootstrap.dart';
import 'frontend_server_client.dart';

class WebDevFS {
  WebDevFS({
    required this.fileSystem,
    required this.hostname,
    required this.port,
    required this.projectDirectory,
    required this.packageUriMapper,
    required this.index,
    required this.soundNullSafety,
    this.urlTunneler,
    required this.sdkLayout,
    required this.ddcModuleFormat,
  });

  final FileSystem fileSystem;
  late final TestAssetServer assetServer;
  final String hostname;
  final int port;
  final Uri projectDirectory;
  final PackageUriMapper packageUriMapper;
  final String index;
  final UrlEncoder? urlTunneler;
  final bool soundNullSafety;
  final TestSdkLayout sdkLayout;
  final ModuleFormat ddcModuleFormat;
  late final Directory _savedCurrentDirectory;

  Future<Uri> create() async {
    _savedCurrentDirectory = fileSystem.currentDirectory;

    fileSystem.currentDirectory = projectDirectory.toFilePath();

    assetServer = await TestAssetServer.start(
      sdkLayout.sdkDirectory,
      fileSystem,
      index,
      hostname,
      port,
      urlTunneler,
      packageUriMapper,
    );
    return Uri.parse('http://$hostname:$port');
  }

  Future<void> dispose() {
    fileSystem.currentDirectory = _savedCurrentDirectory;
    return assetServer.close();
  }

  Future<UpdateFSReport> update({
    required Uri mainUri,
    required String dillOutputPath,
    required ResidentCompiler generator,
    required List<Uri> invalidatedFiles,
  }) async {
    final mainPath = mainUri.toFilePath();
    final outputDirectoryPath = fileSystem.file(mainPath).parent.path;
    final entryPoint = mainUri.toString();

    var ddcModuleLoader = 'ddc_module_loader.js';
    var require = 'require.js';
    var stackMapper = 'stack_trace_mapper.js';
    var main = 'main.dart.js';
    var bootstrap = 'main_module.bootstrap.js';

    // If base path is not overwritten, use main's subdirectory
    // to store all files, so the paths match the requests.
    if (assetServer.basePath.isEmpty) {
      final directory = p.dirname(entryPoint);
      ddcModuleLoader = '$directory/ddc_module_loader.js';
      require = '$directory/require.js';
      stackMapper = '$directory/stack_trace_mapper.js';
      main = '$directory/main.dart.js';
      bootstrap = '$directory/main_module.bootstrap.js';
    }

    assetServer.writeFile(
        entryPoint, fileSystem.file(mainPath).readAsStringSync());
    assetServer.writeFile(stackMapper, stackTraceMapper.readAsStringSync());

    switch (ddcModuleFormat) {
      case ModuleFormat.amd:
        assetServer.writeFile(require, requireJS.readAsStringSync());
        assetServer.writeFile(
          main,
          generateBootstrapScript(
            requireUrl: 'require.js',
            mapperUrl: 'stack_trace_mapper.js',
            entrypoint: entryPoint,
          ),
        );
        assetServer.writeFile(
          bootstrap,
          generateMainModule(
            entrypoint: entryPoint,
          ),
        );
        break;
      case ModuleFormat.ddc:
        assetServer.writeFile(
            ddcModuleLoader, ddcModuleLoaderJS.readAsStringSync());
        assetServer.writeFile(
          main,
          generateDDCBootstrapScript(
            ddcModuleLoaderUrl: ddcModuleLoader,
            mapperUrl: stackMapper,
            entrypoint: entryPoint,
            bootstrapUrl: bootstrap,
          ),
        );
        // DDC uses a simple heuristic to determine exported identifier names.
        // The module name (entrypoint name here) has its extension removed, and
        // special path elements like '/', '\', and '..' are replaced with '__'.
        final exportedMainName = pathToJSIdentifier(entryPoint.split('.')[0]);
        assetServer.writeFile(
          bootstrap,
          generateDDCMainModule(
              entrypoint: entryPoint, exportedMain: exportedMainName),
        );
        break;
      default:
        throw Exception('Unsupported DDC module format $ddcModuleFormat.');
    }

    assetServer.writeFile('main_module.digests', '{}');

    var sdk = soundNullSafety ? dartSdk : dartSdkWeak;
    var sdkSourceMap =
        soundNullSafety ? dartSdkSourcemap : dartSdkSourcemapWeak;
    assetServer.writeFile('dart_sdk.js', sdk.readAsStringSync());
    assetServer.writeFile('dart_sdk.js.map', sdkSourceMap.readAsStringSync());

    generator.reset();
    var compilerOutput = await generator.recompile(
      Uri.parse('org-dartlang-app:///$mainUri'),
      invalidatedFiles,
      outputPath: p.join(dillOutputPath, 'app.dill'),
      packageConfig: packageUriMapper.packageConfig,
    );
    if (compilerOutput == null || compilerOutput.errorCount > 0) {
      return UpdateFSReport(success: false);
    }

    File codeFile;
    File manifestFile;
    File sourcemapFile;
    File metadataFile;
    List<String> modules;
    try {
      var parentDirectory = fileSystem.directory(outputDirectoryPath);
      codeFile =
          parentDirectory.childFile('${compilerOutput.outputFilename}.sources');
      manifestFile =
          parentDirectory.childFile('${compilerOutput.outputFilename}.json');
      sourcemapFile =
          parentDirectory.childFile('${compilerOutput.outputFilename}.map');
      metadataFile = parentDirectory
          .childFile('${compilerOutput.outputFilename}.metadata');
      modules = assetServer.write(
          codeFile, manifestFile, sourcemapFile, metadataFile);
    } on FileSystemException catch (err) {
      throw Exception('Failed to load recompiled sources:\n$err');
    }
    return UpdateFSReport(
      success: true,
      syncedBytes: codeFile.lengthSync(),
      invalidatedSourcesCount: invalidatedFiles.length,
    )..invalidatedModules = modules;
  }

  File get ddcModuleLoaderJS =>
      fileSystem.file(sdkLayout.ddcModuleLoaderJsPath);
  File get requireJS => fileSystem.file(sdkLayout.requireJsPath);
  File get dartSdkWeak => fileSystem.file(switch (ddcModuleFormat) {
        ModuleFormat.amd => sdkLayout.weakAmdJsPath,
        ModuleFormat.ddc => sdkLayout.weakDdcJsPath,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      });
  File get dartSdk => fileSystem.file(switch (ddcModuleFormat) {
        ModuleFormat.amd => sdkLayout.soundAmdJsPath,
        ModuleFormat.ddc => sdkLayout.soundDdcJsPath,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      });
  File get dartSdkSourcemapWeak => fileSystem.file(switch (ddcModuleFormat) {
        ModuleFormat.amd => sdkLayout.weakAmdJsMapPath,
        ModuleFormat.ddc => sdkLayout.weakDdcJsMapPath,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      });
  File get dartSdkSourcemap => fileSystem.file(switch (ddcModuleFormat) {
        ModuleFormat.amd => sdkLayout.soundAmdJsMapPath,
        ModuleFormat.ddc => sdkLayout.soundDdcJsMapPath,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      });
  File get stackTraceMapper => fileSystem.file(sdkLayout.stackTraceMapperPath);
}

class UpdateFSReport {
  final bool _success;
  final int _invalidatedSourcesCount;
  final int _syncedBytes;

  UpdateFSReport({
    bool success = false,
    int invalidatedSourcesCount = 0,
    int syncedBytes = 0,
  })  : _success = success,
        _invalidatedSourcesCount = invalidatedSourcesCount,
        _syncedBytes = syncedBytes;

  bool get success => _success;
  int get invalidatedSourcesCount => _invalidatedSourcesCount;
  int get syncedBytes => _syncedBytes;

  /// JavaScript modules produced by the incremental compiler in `dartdevc`
  /// mode.
  ///
  /// Only used for JavaScript compilation.
  List<String>? invalidatedModules;
}
