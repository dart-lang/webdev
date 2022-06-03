// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests,
// and some functionality remioved (does not support hot reload yet)

import 'dart:async';

import 'package:dwds/asset_reader.dart';
import 'package:dwds/expression_compiler.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'devfs.dart';
import 'frontend_server_client.dart';
import 'utilities.dart';

final Uri platformDillUnsound =
    Uri.file(p.join(dartSdkPath, 'lib', '_internal', 'ddc_sdk.dill'));
final Uri platformDillSound =
    Uri.file(p.join(dartSdkPath, 'lib', '_internal', 'ddc_outline_sound.dill'));

Logger _logger = Logger('ResidentWebRunner');

class ResidentWebRunner {
  ResidentWebRunner(
      this.mainPath,
      this.urlTunneller,
      this.packageConfigPath,
      this.fileSystemRoots,
      this.fileSystemScheme,
      this.outputPath,
      this.soundNullSafety,
      bool verbose) {
    generator = ResidentCompiler(dartSdkPath,
        packageConfigPath: packageConfigPath,
        platformDill:
            soundNullSafety ? '$platformDillSound' : '$platformDillUnsound',
        fileSystemRoots: fileSystemRoots,
        fileSystemScheme: fileSystemScheme,
        verbose: verbose);
    expressionCompiler = TestExpressionCompiler(generator);
  }

  final UrlEncoder urlTunneller;
  final String mainPath;
  final String packageConfigPath;
  final String outputPath;
  final List<String> fileSystemRoots;
  final String fileSystemScheme;
  final bool soundNullSafety;

  late ResidentCompiler generator;
  late ExpressionCompiler expressionCompiler;
  late WebDevFS devFS;
  late Uri uri;
  late Iterable<String> modules;

  Future<int> run(String? hostname, int port, String root) async {
    hostname ??= 'localhost';

    devFS = WebDevFS(
      fileSystem: fileSystem,
      hostname: hostname,
      port: port,
      packageConfigPath: packageConfigPath,
      root: root,
      urlTunneller: urlTunneller,
      soundNullSafety: soundNullSafety,
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
        mainPath: mainPath,
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
