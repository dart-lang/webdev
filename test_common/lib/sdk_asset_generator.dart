import 'dart:convert';
import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test_common/test_sdk_layout.dart';

/// Generates sdk.js, sdk.map, sdk full dill, and sdk summary files.
///
/// Generates following missing assets if needed:
/// - sound null safety: js, source map, full dill.
/// - weak null safety: js, source map, full dill, summary.
class SdkAssetGenerator {
  bool _sdkAssetsGenerated = false;
  final _logger = Logger('SdkAssetGenerator');

  final FileSystem fileSystem;
  final bool canaryFeatures;
  final ModuleFormat ddcModuleFormat;
  final bool verbose;

  late final TestSdkLayout sdkLayout;

  SdkAssetGenerator({
    this.fileSystem = const LocalFileSystem(),
    required this.sdkLayout,
    required this.canaryFeatures,
    required this.ddcModuleFormat,
    this.verbose = false,
  });

  /// Generate all SDK assets, once for the current executable run.
  Future<void> generateSdkAssets() async {
    if (!_sdkAssetsGenerated) {
      _sdkAssetsGenerated = true;

      // SDK contains sound summary, but SDK js and full dill are
      // normally generated by setup tools and their builds,
      // i.e. flutter SDK or build_web_compilers.
      // Generate missing files for tests if needed.
      await _generateSdkJavaScript(
        soundNullSafety: true,
        canaryFeatures: canaryFeatures,
      );

      // SDK does not contain any weak assets, generate them.
      await _generateSdkJavaScript(
        soundNullSafety: false,
        canaryFeatures: canaryFeatures,
      );
      await _generateSdkSummary(soundNullSafety: false);
    }
  }

  String resolveSdkJsPath({
    required bool soundNullSafety,
    required bool canaryFeatures,
  }) =>
      switch ((soundNullSafety, ddcModuleFormat)) {
        (true, ModuleFormat.amd) => sdkLayout.soundAmdJsPath,
        (false, ModuleFormat.amd) => sdkLayout.weakAmdJsPath,
        (true, ModuleFormat.ddc) => sdkLayout.soundDdcJsPath,
        (false, ModuleFormat.ddc) => sdkLayout.weakDdcJsPath,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      };

  String resolveSdkSourcemapPath({
    required bool soundNullSafety,
    required bool canaryFeatures,
  }) =>
      switch ((soundNullSafety, ddcModuleFormat)) {
        (true, ModuleFormat.amd) => sdkLayout.soundAmdJsMapPath,
        (false, ModuleFormat.amd) => sdkLayout.weakAmdJsMapPath,
        (true, ModuleFormat.ddc) => sdkLayout.soundDdcJsMapPath,
        (false, ModuleFormat.ddc) => sdkLayout.weakDdcJsMapPath,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      };

  String resolveSdkJsFilename({
    required bool soundNullSafety,
    required bool canaryFeatures,
  }) =>
      switch ((soundNullSafety, ddcModuleFormat)) {
        (true, ModuleFormat.amd) => sdkLayout.soundAmdJsFileName,
        (false, ModuleFormat.amd) => sdkLayout.weakAmdJsFileName,
        (true, ModuleFormat.ddc) => sdkLayout.soundDdcJsFileName,
        (false, ModuleFormat.ddc) => sdkLayout.weakDdcJsFileName,
        _ => throw Exception('Unsupported DDC module format $ddcModuleFormat.')
      };

  Future<void> _generateSdkJavaScript({
    required bool soundNullSafety,
    required bool canaryFeatures,
  }) async {
    Directory? outputDir;
    try {
      // Files to copy generated files to.
      final outputJsPath = resolveSdkJsPath(
          soundNullSafety: soundNullSafety, canaryFeatures: canaryFeatures);
      final outputJsMapPath = resolveSdkSourcemapPath(
          soundNullSafety: soundNullSafety, canaryFeatures: canaryFeatures);
      final outputFullDillPath = soundNullSafety
          ? sdkLayout.soundFullDillPath
          : sdkLayout.weakFullDillPath;

      final hasJsAsset = _exists(outputJsPath);
      final hasJsMapAsset = _exists(outputJsMapPath);
      final hasFullDillAsset = _exists(outputFullDillPath);
      final hasAssets = hasFullDillAsset && hasJsAsset && hasJsMapAsset;

      // Files already exist.
      if (hasAssets) return;

      // Generate missing files.
      outputDir = fileSystem.systemTempDirectory.createTempSync();

      // Files to generate
      final jsPath = p.join(
          outputDir.path,
          resolveSdkJsFilename(
              soundNullSafety: soundNullSafety,
              canaryFeatures: canaryFeatures));
      final jsMapPath = p.setExtension(jsPath, '.js.map');
      final fullDillPath = p.setExtension(jsPath, '.dill');

      _logger.info('Generating js and full dill SDK files...');

      final sdkDirectoryUri = fileSystem.directory(sdkLayout.sdkDirectory).uri;
      final args = <String>[
        sdkLayout.dartdevcSnapshotPath,
        '--compile-sdk',
        '--multi-root',
        '$sdkDirectoryUri',
        '--multi-root-scheme',
        'org-dartlang-sdk',
        '--libraries-file',
        'org-dartlang-sdk:///lib/libraries.json',
        '--modules',
        ddcModuleFormat.name,
        soundNullSafety ? '--sound-null-safety' : '--no-sound-null-safety',
        'dart:core',
        '-o',
        jsPath,
        if (canaryFeatures) '--canary',
      ];

      final output = <String>[];
      _logger.fine('Executing dart ${args.join(' ')}');
      final process = await Process.start(sdkLayout.dartPath, args,
          workingDirectory: sdkLayout.sdkDirectory);

      process.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((line) {
        _logger.fine(line);
        output.add(line);
      });

      process.stderr
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((line) {
        _logger.warning(line);
        output.add(line);
      });

      await process.exitCode.then((int code) {
        if (code != 0) {
          _logger.warning('Error generating $jsPath: ${output.join('\n')}');
          throw Exception('The Dart compiler exited unexpectedly');
        }
      });

      final outputJsDir = fileSystem.directory(p.dirname(outputJsPath));
      if (!outputJsDir.existsSync()) {
        outputJsDir.createSync(recursive: true);
      }
      await _moveAndValidate(jsPath, outputJsPath);
      await _moveAndValidate(jsMapPath, outputJsMapPath);
      await _moveAndValidate(fullDillPath, outputFullDillPath);

      _logger.info('Done generating js and full dill SDK files.');
    } catch (e, s) {
      _logger.severe(
          'Failed to generate SDK js, source map, and full dill', e, s);
      rethrow;
    } finally {
      outputDir?.deleteSync(recursive: true);
    }
  }

  Future<void> _generateSdkSummary({required bool soundNullSafety}) async {
    Directory? outputDir;
    try {
      // Files to copy generated files to.
      final outputSummaryPath = soundNullSafety
          ? sdkLayout.soundSummaryPath
          : sdkLayout.weakSummaryPath;
      final hasAssets = _exists(outputSummaryPath);

      // Files already exist.
      if (hasAssets) return;

      // Generate missing files.
      outputDir = fileSystem.systemTempDirectory.createTempSync();
      final summaryPath = soundNullSafety
          ? p.join(outputDir.path, sdkLayout.soundSummaryFileName)
          : p.join(outputDir.path, sdkLayout.weakSummaryFileName);

      _logger.info('Generating SDK summary files...');

      final sdkDirectoryUri = fileSystem.directory(sdkLayout.sdkDirectory).uri;
      final args = <String>[
        sdkLayout.kernelWorkerSnapshotPath,
        '--target',
        'ddc',
        '--multi-root',
        '$sdkDirectoryUri',
        '--multi-root-scheme',
        'org-dartlang-sdk',
        '--libraries-file',
        'org-dartlang-sdk:///lib/libraries.json',
        '--source',
        'dart:core',
        '--summary-only',
        if (soundNullSafety)
          '--sound-null-safety'
        else
          '--no-sound-null-safety',
        '--output',
        summaryPath,
        if (verbose) '--verbose',
      ];

      _logger.fine('Executing dart ${args.join(' ')}');
      final process = await Process.start(sdkLayout.dartPath, args,
          workingDirectory: sdkLayout.sdkDirectory);

      final output = <String>[];
      process.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((line) {
        _logger.fine(line);
        output.add(line);
      });

      process.stderr
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((line) {
        _logger.warning(line);
        output.add(line);
      });

      await process.exitCode.then((int code) {
        if (code != 0) {
          _logger
              .warning('Error generating $summaryPath: ${output.join('\n')}');
          throw Exception('The Dart kernel worker exited unexpectedly');
        }
      });

      await _moveAndValidate(summaryPath, outputSummaryPath);

      _logger.info('Done generating SDK summary files.');
    } catch (e, s) {
      _logger.severe('Failed to generate SDK summary', e, s);
      rethrow;
    } finally {
      outputDir?.deleteSync(recursive: true);
    }
  }

  bool _exists(String path) => fileSystem.file(path).existsSync();
  void _delete(String path) => fileSystem.file(path).deleteSync();

  Future<void> _moveAndValidate(String from, String to) async {
    _logger.fine('Renaming $from to $to');

    if (!_exists(from)) {
      _logger.severe('Failed to generate SDK asset at $to');
      throw Exception('File "$from" does not exist.');
    }

    if (_exists(to)) _delete(to);
    await fileSystem.file(from).rename(to);

    if (!_exists(to)) {
      _logger.severe('Failed to generate SDK asset at $to');
      throw Exception('File "$to" does not exist.');
    }
  }
}
