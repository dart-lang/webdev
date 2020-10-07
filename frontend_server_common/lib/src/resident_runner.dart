// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests,
// and some functionality remioved (does not support hot reload yet)

import 'dart:async';

import 'package:dwds/dwds.dart';
import 'package:path/path.dart' as p;

import 'asset.dart';
import 'devfs.dart';
import 'devfs_content.dart';
import 'frontend_server_client.dart';
import 'utilities.dart';

final Uri platformDill =
    Uri.file(p.join(dartSdkPath, 'lib', '_internal', 'ddc_sdk.dill'));

class ResidentWebRunner {
  ResidentWebRunner(
      this.mainPath,
      this.urlTunneller,
      this.packagesPath,
      this.packagesFilePath,
      this.fileSystemRoots,
      this.fileSystemScheme,
      this.outputPath,
      this.logWriter,
      bool verbose) {
    generator = ResidentCompiler(dartSdkPath, logWriter,
        packagesPath: packagesPath,
        platformDill: '$platformDill',
        fileSystemRoots: fileSystemRoots,
        fileSystemScheme: fileSystemScheme,
        verbose: verbose);
    expressionCompiler = TestExpressionCompiler(generator);
  }

  final LogWriter logWriter;
  final UrlEncoder urlTunneller;
  final String mainPath;
  final String packagesPath;
  final String packagesFilePath;
  final String outputPath;
  final List<String> fileSystemRoots;
  final String fileSystemScheme;

  ResidentCompiler generator;
  ExpressionCompiler expressionCompiler;
  AssetBundle assetBundle;
  WebDevFS devFS;
  Uri uri;
  Iterable<String> modules;

  Future<int> run(String hostname, int port, String root) async {
    hostname ??= 'localhost';

    assetBundle = AssetBundleFactory.defaultInstance.createBundle();

    devFS = WebDevFS(
        fileSystem: fileSystem,
        hostname: hostname,
        port: port,
        packagesFilePath: packagesFilePath,
        packagesPath: packagesPath,
        root: root,
        urlTunneller: urlTunneller,
        logWriter: logWriter);
    uri = await devFS.create();

    var report = await _updateDevFS();
    if (!report.success) {
      printError('Failed to compile application.');
      return 1;
    }

    modules = report.invalidatedModules;

    generator.accept();
    return 0;
  }

  Future<UpdateFSReport> _updateDevFS() async {
    var result = await assetBundle.build();
    if (result != 0) {
      return UpdateFSReport(success: false);
    }

    var report = await devFS.update(
        mainPath: mainPath,
        bundle: assetBundle,
        dillOutputPath: outputPath,
        generator: generator,
        invalidatedFiles: []);
    return report;
  }

  Future<void> stop() async {
    await generator.shutdown();
    await devFS.dispose();
  }
}
