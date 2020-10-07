// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'asset.dart';
import 'asset_server.dart';
import 'bootstrap.dart';
import 'devfs_content.dart';
import 'frontend_server_client.dart';
import 'utilities.dart';

final String dartWebSdkPath = p.join(dartSdkPath, 'lib', 'dev_compiler');

class WebDevFS {
  WebDevFS(
      {this.fileSystem,
      this.hostname,
      this.port,
      this.packagesFilePath,
      this.packagesPath,
      this.root,
      this.urlTunneller,
      this.logWriter});

  final FileSystem fileSystem;
  TestAssetServer assetServer;
  final String hostname;
  final int port;
  final String packagesFilePath;
  final String packagesPath;
  final String root;
  final UrlEncoder urlTunneller;
  final LogWriter logWriter;
  Directory _savedCurrentDirectory;
  List<Uri> sources;

  Future<Uri> create() async {
    _savedCurrentDirectory = fileSystem.currentDirectory;
    fileSystem.currentDirectory = packagesPath;
    assetServer = await TestAssetServer.start(
        fileSystem, root, hostname, port, urlTunneller, logWriter);
    return Uri.parse('http://$hostname:$port');
  }

  Future<void> dispose() {
    fileSystem.currentDirectory = _savedCurrentDirectory;
    return assetServer.close();
  }

  Future<UpdateFSReport> update({
    String mainPath,
    AssetBundle bundle,
    String dillOutputPath,
    @required ResidentCompiler generator,
    List<Uri> invalidatedFiles,
  }) async {
    assert(generator != null);
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
    assetServer.writeFile('/dart_sdk.js', dartSdk.readAsStringSync());
    assetServer.writeFile(
        '/dart_sdk.js.map', dartSdkSourcemap.readAsStringSync());
    // TODO(jonahwilliams): refactor the asset code in this and the regular devfs to
    // be shared.
    if (bundle != null) {
      await writeBundle(
        fileSystem.directory(p.joinAll(['build', 'assets'])),
        bundle.entries,
      );
    }

    generator.reset();

    var compilerOutput = await generator.recompile(
      'org-dartlang-app:///$mainPath',
      invalidatedFiles,
      outputPath: p.join(dillOutputPath, 'app.dill'),
      packagesFilePath: packagesFilePath,
    );
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

  File get dartSdkSourcemap => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'kernel',
        'amd',
        'dart_sdk.js.map',
      ));

  File get stackTraceMapper => fileSystem.file(fileSystem.path.join(
        dartWebSdkPath,
        'web',
        'dart_stack_trace_mapper.js',
      ));
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

Future<void> writeBundle(
    Directory bundleDir, Map<String, DevFSContent> assetEntries) async {
  if (bundleDir.existsSync()) {
    try {
      bundleDir.deleteSync(recursive: true);
    } on FileSystemException catch (err) {
      printError('Failed to clean up asset directory ${bundleDir.path}: $err\n'
          'To clean build artifacts, use the command "flutter clean".');
    }
  }
  bundleDir.createSync(recursive: true);

  await Future.wait<void>(assetEntries.entries
      .map<Future<void>>((MapEntry<String, DevFSContent> entry) async {
    var file = fileSystem.file(fileSystem.path.join(bundleDir.path, entry.key));
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(await entry.value.contentsAsBytes());
  }));
}
