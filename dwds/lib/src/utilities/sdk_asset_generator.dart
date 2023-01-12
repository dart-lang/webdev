import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Generates sdk.js, sdk.map, and sdk summary files.
///
/// Missing assets:
/// mode\env | test (FE server) | test (build daemon) | test (webdev)
/// -----------------------------------------------------------------
/// strong   | js               |                     |
/// weak     | js, summary      | summary             | summary (TODO)
/// -----------------------------------------------------------------
class SdkAssetGenerator {
  static bool _sdkAssetsGenerated = false;
  final _logger = Logger('SdkAssetGenerator');

  final _sdkJsWeakFileName = 'dart_sdk.js';
  final _sdkJsMapWeakFileName = 'dart_sdk.js.map';
  final _sdkJsSoundFileName = 'dart_sdk_sound.js';
  final _sdkJsMapSoundFileName = 'dart_sdk_sound.js.map';

  final FileSystem fileSystem;
  final String sdkDirectory;
  final bool verboseCompiler;

  final String soundAssetDirectory;
  final String weakAssetDirectory;
  final String dartSdkJsDirectory;

  String get soundSummaryPath =>
      p.join(soundAssetDirectory, 'ddc_outline_sound.dill');
  String get soundFullDillPath =>
      p.join(soundAssetDirectory, 'ddc_platform_sound.dill');
  String get soundJsPath => p.join(dartSdkJsDirectory, _sdkJsSoundFileName);
  String get soundJsMapPath =>
      p.join(dartSdkJsDirectory, _sdkJsMapSoundFileName);

  String get weakSummaryPath => p.join(weakAssetDirectory, 'ddc_sdk.dill');
  String get weakFullDillPath =>
      p.join(weakAssetDirectory, 'ddc_platform.dill');
  String get weakJsPath => p.join(dartSdkJsDirectory, _sdkJsWeakFileName);
  String get weakJsMapPath => p.join(dartSdkJsDirectory, _sdkJsMapWeakFileName);

  String get dartdevcSnapshotPath =>
      p.join(sdkDirectory, 'bin', 'snapshots', 'dartdevc.dart.snapshot');
  String get kernelWorkerSnapshotPath =>
      p.join(sdkDirectory, 'bin', 'snapshots', 'kernel_worker.dart.snapshot');

  SdkAssetGenerator({
    this.fileSystem = const LocalFileSystem(),
    required this.sdkDirectory,
    this.verboseCompiler = false,
  })  : soundAssetDirectory = p.join(sdkDirectory, 'lib', '_internal'),
        weakAssetDirectory = p.join(sdkDirectory, 'lib', '_internal'),
        dartSdkJsDirectory =
            p.join(sdkDirectory, 'lib', 'dev_compiler', 'kernel', 'amd');

  /// Generate all SDK assets, once for the current executable run.
  Future<void> generateSdkAssets() async {
    if (!_sdkAssetsGenerated) {
      _sdkAssetsGenerated = true;

      for (var soundNullSafety in [true, false]) {
        await _generateSdkJavaScript(soundNullSafety);
        await _generateSdkSummary(soundNullSafety);
      }
    }
  }

  void _deleteIfExists(String path) {
    final file = fileSystem.file(path);
    if (file.existsSync()) file.deleteSync();
  }

  Future<void> _generateSdkJavaScript(bool soundNullSafety) async {
    // Files to generate
    final jsPath = soundNullSafety
        ? p.join(soundAssetDirectory, _sdkJsSoundFileName)
        : p.join(soundAssetDirectory, _sdkJsWeakFileName);
    final jsMapPath = p.setExtension(jsPath, '.js.map');
    final fullDillPath = p.setExtension(jsPath, '.dill');

    // File to copy generate files to.
    final newJsPath = soundNullSafety ? soundJsPath : weakJsPath;
    final newJsMapPath = soundNullSafety ? soundJsMapPath : weakJsMapPath;
    final newFullDillPath =
        soundNullSafety ? soundFullDillPath : weakFullDillPath;

    // TODO(annagrin) Generate only if needed.
    if (!soundNullSafety) {
      _deleteIfExists(fullDillPath);
      _deleteIfExists(newFullDillPath);
    }
    {
      _deleteIfExists(jsPath);
      _deleteIfExists(newJsPath);
      _deleteIfExists(jsMapPath);
      _deleteIfExists(newJsMapPath);
    }

    final args = <String>[
      dartdevcSnapshotPath,
      '--compile-sdk',
      '--multi-root',
      sdkDirectory,
      '--multi-root-scheme',
      'org-dartlang-sdk',
      '--libraries-file',
      'org-dartlang-sdk:///lib/libraries.json',
      '--modules',
      'amd',
      // Sound full dill file is included in the SDK,
      // we only create one for weak mode.
      // This creates full dill file in '$fullDillPath'.
      if (!soundNullSafety) '--summarize',
      if (soundNullSafety) '--sound-null-safety',
      if (!soundNullSafety) '--no-sound-null-safety',
      'dart:core',
      '-o',
      jsPath,
    ];

    _logger.info('Executing dart ${args.join(' ')}');
    final process = await Process.start(Platform.resolvedExecutable, args,
        workingDirectory: sdkDirectory);

    process.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_logger.fine);

    process.stderr
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_logger.warning);

    await process.exitCode.then((int code) {
      if (code != 0) {
        _logger.warning('Cannot generate SDK full dill and js'
            'with ${soundNullSafety ? 'sound' : 'weak'} null safety');
        throw Exception('the Dart compiler exited unexpectedly.');
      }
    });

    if (!soundNullSafety) {
      _logger.fine('Renaming $fullDillPath to $newFullDillPath');
      await fileSystem.file(fullDillPath).rename(newFullDillPath);
    }

    _logger.fine('Renaming $jsPath to $newJsPath');
    await fileSystem.file(jsPath).rename(newJsPath);

    _logger.fine('Renaming $jsMapPath to $newJsMapPath');
    await fileSystem.file(jsMapPath).rename(newJsMapPath);
  }

  Future<void> _generateSdkSummary(bool soundNullSafety) async {
    // Sound summary is included in the SDK
    if (soundNullSafety) return;

    final summaryPath = soundNullSafety ? soundSummaryPath : weakSummaryPath;
    // TODO(annagrin) Generate only if needed.
    _deleteIfExists(summaryPath);

    final args = <String>[
      kernelWorkerSnapshotPath,
      '--target',
      'ddc',
      '--multi-root',
      sdkDirectory,
      '--multi-root-scheme',
      'org-dartlang-sdk',
      '--libraries-file',
      'org-dartlang-sdk:///lib/libraries.json',
      '--source',
      'dart:core',
      '--summary-only',
      if (soundNullSafety) '--sound-null-safety',
      if (!soundNullSafety) '--no-sound-null-safety',
      '--output',
      summaryPath,
      if (verboseCompiler) '--verbose',
    ];

    _logger.info('Executing dart ${args.join(' ')}');
    final process = await Process.start(Platform.resolvedExecutable, args,
        workingDirectory: sdkDirectory);

    process.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_logger.fine);

    process.stderr
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_logger.warning);

    await process.exitCode.then((int code) {
      if (code != 0) {
        _logger.severe('Cannot generate SDK summary'
            'with ${soundNullSafety ? 'sound' : 'weak'} null safety');
        throw Exception('the Dart kernel worker exited unexpectedly.');
      }
    });
  }
}
