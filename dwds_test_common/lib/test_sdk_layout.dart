// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dwds/sdk_configuration.dart';
import 'package:path/path.dart' as p;

/// Test Dart SDK layout.
///
/// Contains definition of the default SDK layout required for tests.
/// We keep all the path constants in one place for ease of update.
class TestSdkLayout {
  static final defaultSdkDirectory = _getDefaultSdkDirectory();

  static String _getDefaultSdkDirectory() {
    // When running tests in Google3, the TEST_SRCDIR environment variable
    // provides the absolute path to the root of the runfiles tree during tests
    // executions. We use it to locate the Dart SDK within the test sandbox.
    final testSrcDir = Platform.environment['TEST_SRCDIR'];
    if (testSrcDir != null) {
      final g3SdkDir = p.join(
        testSrcDir,
        'google3',
        'third_party',
        'dart_lang',
        'v2',
        'sdk',
      );
      if (Directory(g3SdkDir).existsSync()) return g3SdkDir;
    }
    return SdkLayout.defaultSdkDirectory;
  }

  static TestSdkLayout defaultSdkLayout = TestSdkLayout.createDefault(
    defaultSdkDirectory,
  );

  static SdkConfiguration defaultSdkConfiguration = createConfiguration(
    defaultSdkLayout,
  );

  factory TestSdkLayout.createDefault(String sdkDirectory) =>
      TestSdkLayout.createDefaultFromSdkLayout(
        SdkLayout.createDefault(sdkDirectory),
      );

  factory TestSdkLayout.createDefaultFromSdkLayout(SdkLayout sdkLayout) =>
      TestSdkLayout(
        sdkDirectory: sdkLayout.sdkDirectory,
        summaryPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          '_internal',
          'ddc_outline.dill',
        ),
        fullDillPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          '_internal',
          'ddc_platform.dill',
        ),
        amdJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk.js',
        ),
        amdJsMapPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk.js.map',
        ),
        ddcJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'ddc',
          'dart_sdk.js',
        ),
        ddcJsMapPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'ddc',
          'dart_sdk.js.map',
        ),
        ddcModuleLoaderJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'ddc',
          'ddc_module_loader.js',
        ),
        requireJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'amd',
          'require.js',
        ),
        stackTraceMapperPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'web',
          'dart_stack_trace_mapper.js',
        ),
        dartPath: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          Platform.isWindows ? 'dart.exe' : 'dart',
        ),
        dartAotRuntimePath: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          Platform.isWindows ? 'dartaotruntime.exe' : 'dartaotruntime',
        ),
        frontendServerSnapshotPath: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          'snapshots',
          'frontend_server_aot.dart.snapshot',
        ),
        dartdevcSnapshotPath: sdkLayout.dartdevcSnapshotPath,
        kernelWorkerSnapshotPath: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          'snapshots',
          'kernel_worker_aot.dart.snapshot',
        ),
        devToolsDirectory: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          'resources',
          'devtools',
        ),
      );

  final String sdkDirectory;

  String get amdJsFileName => p.basename(amdJsPath);
  String get amdJsMapFileName => p.basename(amdJsMapPath);
  String get ddcJsFileName => p.basename(ddcJsPath);
  String get ddcJsMapFileName => p.basename(ddcJsMapPath);
  String get summaryFileName => p.basename(summaryPath);
  String get fullDillFileName => p.basename(fullDillPath);

  final String amdJsPath;
  final String amdJsMapPath;
  final String ddcJsPath;
  final String ddcJsMapPath;
  final String summaryPath;
  final String fullDillPath;

  final String ddcModuleLoaderJsPath;
  final String requireJsPath;
  final String stackTraceMapperPath;

  final String dartPath;
  final String dartAotRuntimePath;
  final String frontendServerSnapshotPath;
  final String dartdevcSnapshotPath;
  final String kernelWorkerSnapshotPath;
  final String devToolsDirectory;

  const TestSdkLayout({
    required this.sdkDirectory,
    required this.amdJsPath,
    required this.amdJsMapPath,
    required this.ddcJsPath,
    required this.ddcJsMapPath,
    required this.summaryPath,
    required this.fullDillPath,
    required this.ddcModuleLoaderJsPath,
    required this.requireJsPath,
    required this.stackTraceMapperPath,
    required this.dartPath,
    required this.dartAotRuntimePath,
    required this.frontendServerSnapshotPath,
    required this.dartdevcSnapshotPath,
    required this.kernelWorkerSnapshotPath,
    required this.devToolsDirectory,
  });

  /// Creates configuration from sdk layout.
  static SdkConfiguration createConfiguration(TestSdkLayout sdkLayout) =>
      SdkConfiguration(
        sdkDirectory: sdkLayout.sdkDirectory,
        sdkSummaryPath: sdkLayout.summaryPath,
        compilerWorkerPath: sdkLayout.dartdevcSnapshotPath,
      );
}

// Update modified files.
Future<void> copyDirectory(String from, String to) async {
  // If running in a Google3 environment, augment the copied SDK with required
  // artifacts that might be missing or in different locations compared to the
  // standard SDK layout.
  final testSrcDir = Platform.environment['TEST_SRCDIR'];
  if (testSrcDir != null && from == TestSdkLayout.defaultSdkDirectory) {
    await _copyGoogle3Artifacts(testSrcDir, to);
    _createGoogle3DummyFiles(to);
  }

  await _copyDirectory(from, to);
}

Future<void> _copyDirectory(String from, String to) async {
  if (!Directory(from).existsSync()) return;
  await Directory(to).create(recursive: true);

  await for (final file in Directory(from).list(followLinks: false)) {
    final copyTo = p.join(to, p.relative(file.path, from: from));
    if (file is Directory) {
      await _copyDirectory(file.path, copyTo);
    } else if (file is File) {
      await File(file.path).copy(copyTo);
    } else if (file is Link) {
      await Link(copyTo).create(await file.target(), recursive: true);
    }
  }
}

void _createGoogle3DummyFiles(String to) {
  // Create a dummy require.js to satisfy the SDK layout checks.
  final requireJs = p.join(to, 'lib', 'dev_compiler', 'amd', 'require.js');
  if (!File(requireJs).existsSync()) {
    File(requireJs).createSync(recursive: true);
  }

  // Create a dummy devtools directory to satisfy the SDK layout checks.
  final devtools = p.join(to, 'bin', 'resources', 'devtools');
  if (!Directory(devtools).existsSync()) {
    Directory(devtools).createSync(recursive: true);
  }
}

Future<void> _copyGoogle3Artifacts(String testSrcDir, String to) async {
  // Copy dart binary from the platform-specific directory
  // (e.g., `linux/sdk/bin`).
  final platform = Platform.isMacOS ? 'darwin' : 'linux';
  final g3DartBinDir = p.join(
    testSrcDir,
    'google3',
    'third_party',
    'dart_lang',
    'v2',
    platform,
    'sdk',
    'bin',
  );
  if (Directory(g3DartBinDir).existsSync()) {
    await _copyDirectory(g3DartBinDir, p.join(to, 'bin'));
  }

  // Copy dartdevc_aot.dart.snapshot. TestSdkLayout checks for
  // 'dartdevc.dart.snapshot', so we copy it under both names.
  final g3DartdevcSnapshot = p.join(
    testSrcDir,
    'google3',
    'third_party',
    'dart',
    'dev_compiler',
    'dartdevc_aot.dart.snapshot',
  );
  if (File(g3DartdevcSnapshot).existsSync()) {
    final snapshotsDir = Directory(p.join(to, 'bin', 'snapshots'));
    if (!snapshotsDir.existsSync()) {
      snapshotsDir.createSync(recursive: true);
    }
    File(
      g3DartdevcSnapshot,
    ).copySync(p.join(snapshotsDir.path, 'dartdevc.dart.snapshot'));
    File(
      g3DartdevcSnapshot,
    ).copySync(p.join(snapshotsDir.path, 'dartdevc_aot.dart.snapshot'));
  }

  // Copy ddc_module_loader.js from the dev_compiler package.
  final ddcLoaderSrc = p.join(
    testSrcDir,
    'google3',
    'third_party',
    'dart',
    'dev_compiler',
    'lib',
    'js',
    'ddc',
    'ddc_module_loader.js',
  );
  final ddcLoaderDst = p.join(
    to,
    'lib',
    'dev_compiler',
    'ddc',
    'ddc_module_loader.js',
  );
  if (!File(ddcLoaderDst).existsSync()) {
    if (File(ddcLoaderSrc).existsSync()) {
      File(ddcLoaderDst).createSync(recursive: true);
      File(ddcLoaderSrc).copySync(ddcLoaderDst);
    }
  }

  // Copy dart_stack_trace_mapper.js from the dev_compiler package's
  // build output (ddc_stack_trace_mapper.js).
  final stackTraceMapperSrc = p.join(
    testSrcDir,
    'google3',
    'third_party',
    'dart',
    'dev_compiler',
    'ddc_stack_trace_mapper.js',
  );
  final stackTraceMapperDst = p.join(
    to,
    'lib',
    'dev_compiler',
    'web',
    'dart_stack_trace_mapper.js',
  );
  if (!File(stackTraceMapperDst).existsSync()) {
    if (File(stackTraceMapperSrc).existsSync()) {
      File(stackTraceMapperDst).createSync(recursive: true);
      File(stackTraceMapperSrc).copySync(stackTraceMapperDst);
    }
  }

  // Copy frontend_server_aot.dart.snapshot from the frontend_server package.
  final frontendServerSrc = p.join(
    testSrcDir,
    'google3',
    'third_party',
    'dart',
    'frontend_server',
    'frontend_server_aot.dart.snapshot',
  );
  final frontendServerDst = p.join(
    to,
    'bin',
    'snapshots',
    'frontend_server_aot.dart.snapshot',
  );
  if (!File(frontendServerDst).existsSync()) {
    if (File(frontendServerSrc).existsSync()) {
      File(frontendServerDst).createSync(recursive: true);
      File(frontendServerSrc).copySync(frontendServerDst);
    }
  }

  // Copy kernel_worker_aot.dart.snapshot from the dart_lang package.
  final kernelWorkerSrc = p.join(
    testSrcDir,
    'google3',
    'third_party',
    'dart_lang',
    'v2',
    'kernel_worker_aot.dart.snapshot',
  );
  final kernelWorkerDst = p.join(
    to,
    'bin',
    'snapshots',
    'kernel_worker_aot.dart.snapshot',
  );
  if (!File(kernelWorkerDst).existsSync()) {
    if (File(kernelWorkerSrc).existsSync()) {
      File(kernelWorkerDst).createSync(recursive: true);
      File(kernelWorkerSrc).copySync(kernelWorkerDst);
    }
  }
}
