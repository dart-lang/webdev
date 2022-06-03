// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'dart:io';

import 'package:dwds/asset_reader.dart';
import 'package:file/file.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import 'asset_server.dart';
import 'bootstrap.dart';
import 'frontend_server_client.dart';
import 'utilities.dart';

final String dartWebSdkPath = p.join(dartSdkPath, 'lib', 'dev_compiler');

class WebDevFS {
  WebDevFS({
    required this.fileSystem,
    required this.hostname,
    required this.port,
    required this.packageConfigPath,
    required this.root,
    required this.urlTunneller,
    required this.soundNullSafety,
  });

  final FileSystem fileSystem;
  late TestAssetServer assetServer;
  final String hostname;
  final int port;
  final String packageConfigPath;
  final String root;
  final UrlEncoder urlTunneller;
  final bool soundNullSafety;
  late Directory _savedCurrentDirectory;
  List<Uri>? sources;
  late PackageConfig _packageConfig;

  Future<Uri> create() async {
    _savedCurrentDirectory = fileSystem.currentDirectory;
    // package_config.json is located in <project directory>/.dart_tool/package_config
    var projectDirectory = p.dirname(p.dirname(packageConfigPath));

    fileSystem.currentDirectory = projectDirectory;

    _packageConfig = await loadPackageConfigUri(Uri.file(packageConfigPath),
        loader: (Uri uri) => fileSystem.file(uri).readAsBytes());

    assetServer = await TestAssetServer.start(
        fileSystem, root, hostname, port, urlTunneller, _packageConfig);
    return Uri.parse('http://$hostname:$port');
  }

  Future<void> dispose() {
    fileSystem.currentDirectory = _savedCurrentDirectory;
    return assetServer.close();
  }

  Future<UpdateFSReport> update({
    required String mainPath,
    required String dillOutputPath,
    required ResidentCompiler generator,
    required List<Uri> invalidatedFiles,
  }) async {
    var outputDirectoryPath = fileSystem.file(mainPath).parent.path;
    var entryPoint = mainPath;

    assetServer.writeFile(
      '/main.dart.js',
      generateBootstrapScript(
        requireUrl: _filePathToUriFragment(requireJS.path),
        mapperUrl: _filePathToUriFragment(stackTraceMapper.path),
        entrypoint: entryPoint,
      ),
    );
    assetServer.writeFile(
      '/main_module.bootstrap.js',
      generateMainModule(
        entrypoint: entryPoint,
      ),
    );

    assetServer.writeFile('/main_module.digests', '{}');
    var sdk = soundNullSafety ? dartSdkSound : dartSdk;
    var sdkSourceMap =
        soundNullSafety ? dartSdkSourcemapSound : dartSdkSourcemap;
    assetServer.writeFile('/dart_sdk.js', sdk.readAsStringSync());
    assetServer.writeFile('/dart_sdk.js.map', sdkSourceMap.readAsStringSync());

    generator.reset();
    var compilerOutput = await generator.recompile(
        Uri.parse('org-dartlang-app:///$mainPath'), invalidatedFiles,
        outputPath: p.join(dillOutputPath, 'app.dill'),
        packageConfig: _packageConfig);
    if (compilerOutput == null || compilerOutput.errorCount > 0) {
      return UpdateFSReport(success: false);
    }

    // list of sources that needs to be monitored are in [compilerOutput.sources]
    sources = compilerOutput.sources;
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

  File get requireJS => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'kernel',
        'amd',
        'require.js',
      ));

  File get dartSdk => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'kernel',
        'amd',
        'dart_sdk.js',
      ));

  File get dartSdkSound => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'kernel',
        'amd',
        'dart_sdk_sound.js',
      ));

  File get dartSdkSourcemap => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'kernel',
        'amd',
        'dart_sdk.js.map',
      ));

  File get dartSdkSourcemapSound => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'kernel',
        'amd',
        'dart_sdk_sound.js.map',
      ));

  File get stackTraceMapper => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'web',
        'dart_stack_trace_mapper.js',
      ));
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

String _filePathToUriFragment(String path) {
  if (Platform.isWindows) {
    var startWithSlash = path.startsWith('/');
    var partial =
        fileSystem.path.split(path).skip(startWithSlash ? 2 : 1).join('/');
    if (partial.startsWith('/')) {
      return partial;
    }
    return '/$partial';
  }
  return path;
}
