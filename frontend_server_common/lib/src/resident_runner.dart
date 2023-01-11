// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests,
// and some functionality removed (does not support hot reload yet)

import 'dart:async';

import 'package:dwds/asset_reader.dart';
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/sdk_configuration.dart';
import 'package:file/file.dart';
import 'package:logging/logging.dart';

import 'devfs.dart';
import 'frontend_server_client.dart';

class ResidentWebRunner {
  final _logger = Logger('ResidentWebRunner');

  ResidentWebRunner(
      this.mainUri,
      this.urlTunneler,
      this.projectDirectory,
      this.packageConfigFile,
      this.packageUriMapper,
      this.fileSystemRoots,
      this.fileSystemScheme,
      this.outputPath,
      this.soundNullSafety,
      this.sdkLayout,
      bool verbose) {
    final sdkSummaryUri = soundNullSafety
        ? Uri.file(sdkLayout.soundSummaryPath)
        : Uri.file(sdkLayout.weakSummaryPath);

    generator = ResidentCompiler(
      sdkLayout.sdkDirectory,
      sdkLayout.dartPath,
      sdkLayout.frontendServerSnapshotPath,
      projectDirectory: projectDirectory,
      packageConfigFile: packageConfigFile,
      useDebuggerModuleNames: packageUriMapper.useDebuggerModuleNames,
      platformDill: '$sdkSummaryUri',
      fileSystemRoots: fileSystemRoots,
      fileSystemScheme: fileSystemScheme,
      verbose: verbose,
      soundNullSafety: soundNullSafety,
    );
    expressionCompiler = TestExpressionCompiler(generator);
  }

  final UrlEncoder? urlTunneler;
  final Uri mainUri;
  final Uri projectDirectory;
  final Uri packageConfigFile;
  final PackageUriMapper packageUriMapper;
  final String outputPath;
  final List<Uri> fileSystemRoots;
  final String fileSystemScheme;
  final bool soundNullSafety;
  final SdkLayout sdkLayout;

  late ResidentCompiler generator;
  late ExpressionCompiler expressionCompiler;
  late WebDevFS devFS;
  late Uri uri;
  late Iterable<String> modules;

  Future<int> run(
      FileSystem fileSystem, String? hostname, int port, String index) async {
    devFS = WebDevFS(
      fileSystem: fileSystem,
      hostname: hostname ?? 'localhost',
      port: port,
      projectDirectory: projectDirectory,
      packageUriMapper: packageUriMapper,
      index: index,
      urlTunneler: urlTunneler,
      soundNullSafety: soundNullSafety,
      sdkLayout: sdkLayout,
    );
    uri = await devFS.create();

    var report = await _updateDevFS();
    if (!report.success) {
      _logger.severe('Failed to compile application.');
      return 1;
    }

    modules = report.invalidatedModules!;

    generator.accept();
    return 0;
  }

  Future<UpdateFSReport> _updateDevFS() async {
    var report = await devFS.update(
        mainUri: mainUri,
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
