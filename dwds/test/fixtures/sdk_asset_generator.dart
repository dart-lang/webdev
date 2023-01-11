import 'dart:convert';
import 'dart:io';

import 'package:dwds/src/utilities/sdk_layout.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Generates sdk.js, sdk.map, sdk full dill, and sdk summary files.
///
/// Generates following missing assets if needed:
/// - sound null safety: js, source map, full dill.
/// - weak null safety: js, source map, full dill, summary.
class SdkAssetGenerator {
  bool _sdkAssetsGenerated = false;
  final _logger = Logger('SdkAssetGenerator');

  final FileSystem fileSystem;
  final bool verboseCompiler;

  late final SdkLayout sdkLayout;

  SdkAssetGenerator({
    this.fileSystem = const LocalFileSystem(),
    required this.sdkLayout,
    this.verboseCompiler = false,
  });

  /// Generate all SDK assets, once for the current executable run.
  Future<void> generateSdkAssets() async {
    if (!_sdkAssetsGenerated) {
      _sdkAssetsGenerated = true;

      // SDK contains sound summary, but SDK js and full dill are
      // normally generated by setup tools and their builds,
      // i.e. flutter SDK or build_web_compilers.
      // Generate missing files for tests if needed.
      await _generateSdkJavaScript(soundNullSafety: true);

      // SDK does not contain any weak assets, generate them.
      await _generateSdkJavaScript(soundNullSafety: false);
      await _generateSdkSummary(soundNullSafety: false);
    }
  }

  Future<void> _generateSdkJavaScript({required bool soundNullSafety}) async {
    Directory? tempOutputDir;
    try {
      // Files to copy generated files to.
      final outputJsPath =
          soundNullSafety ? sdkLayout.soundJsPath : sdkLayout.weakJsPath;
      final outputJsMapPath =
          soundNullSafety ? sdkLayout.soundJsMapPath : sdkLayout.weakJsMapPath;
      final outputFullDillPath = soundNullSafety
          ? sdkLayout.soundFullDillPath
          : sdkLayout.weakFullDillPath;

      final hasJsAsset = _fileExists(outputJsPath);
      final hasJsMapAsset = _fileExists(outputJsMapPath);
      final hasFullDillAsset = _fileExists(outputFullDillPath);
      final hasAssets = hasFullDillAsset && hasJsAsset && hasJsMapAsset;

      // Files already exist.
      if (hasAssets) return;

      // Generate missing files.
      tempOutputDir = fileSystem.systemTempDirectory.createTempSync();

      // Files to generate
      final jsPath = soundNullSafety
          ? p.join(tempOutputDir.path, sdkLayout.soundJsFileName)
          : p.join(tempOutputDir.path, sdkLayout.weakJsFileName);
      final jsMapPath = p.setExtension(jsPath, '.js.map');
      final fullDillPath = p.setExtension(jsPath, '.dill');

      _logger.info('Generating js, source map, and full dill SDK files...');

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
        'amd',
        if (soundNullSafety)
          '--sound-null-safety'
        else
          '--no-sound-null-safety',
        'dart:core',
        '-o',
        jsPath,
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

      // Move generated files to the final destination.
      final outputDir = p.dirname(outputJsPath);
      _createDirectory(outputDir);

      await _moveAndValidate(jsPath, outputJsPath);
      await _moveAndValidate(jsMapPath, outputJsMapPath);
      await _moveAndValidate(fullDillPath, outputFullDillPath);

      _logger.info('Done generating js, source map, and full dill SDK files.');
    } catch (e, s) {
      _logger.severe(
          'Failed to generate SDK js, source map, and full dill', e, s);
      rethrow;
    } finally {
      tempOutputDir?.deleteSync(recursive: true);
    }
  }

  Future<void> _generateSdkSummary({required bool soundNullSafety}) async {
    Directory? tempOutputDir;
    try {
      // Files to copy generated files to.
      final outputSummaryPath = soundNullSafety
          ? sdkLayout.soundSummaryPath
          : sdkLayout.weakSummaryPath;
      final hasAssets = _fileExists(outputSummaryPath);

      // Files already exist.
      if (hasAssets) return;

      // Generate missing files.
      tempOutputDir = fileSystem.systemTempDirectory.createTempSync();
      final summaryPath = soundNullSafety
          ? p.join(tempOutputDir.path, sdkLayout.soundSummaryFileName)
          : p.join(tempOutputDir.path, sdkLayout.weakSummaryFileName);

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
        if (verboseCompiler) '--verbose',
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

      // Move generated files to the final destination.
      final outputDir = p.dirname(outputSummaryPath);
      _createDirectory(outputDir);
      await _moveAndValidate(summaryPath, outputSummaryPath);

      _logger.info('Done generating SDK summary files.');
    } catch (e, s) {
      _logger.severe('Failed to generate SDK summary', e, s);
      rethrow;
    } finally {
      tempOutputDir?.deleteSync(recursive: true);
    }
  }

  bool _fileExists(String path) => fileSystem.file(path).existsSync();
  void _deleteFile(String path) => fileSystem.file(path).deleteSync();
  void _createDirectory(String path) {
    final directory = fileSystem.directory(path);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  Future<void> _moveAndValidate(String from, String to) async {
    _logger.fine('Renaming $from to $to');

    if (_fileExists(to)) _deleteFile(to);
    await fileSystem.file(from).rename(to);

    if (!_fileExists(to)) {
      _logger.severe('Failed to generate SDK asset at $to');
      throw Exception('File does not exist.');
    }
  }
}
