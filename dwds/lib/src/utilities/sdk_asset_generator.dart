import 'dart:convert';
import 'dart:io';

import 'package:dwds/src/utilities/sdk_configuration.dart';
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
    Directory? outputDir;
    try {
      // Files to copy generated files to.
      final outputJsPath =
          soundNullSafety ? sdkLayout.soundJsPath : sdkLayout.weakJsPath;
      final outputJsMapPath =
          soundNullSafety ? sdkLayout.soundJsMapPath : sdkLayout.weakJsMapPath;
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
      final jsPath = soundNullSafety
          ? p.join(outputDir.path, sdkLayout.sdkJsSoundFileName)
          : p.join(outputDir.path, sdkLayout.sdkJsWeakFileName);
      final jsMapPath = p.setExtension(jsPath, '.js.map');
      final fullDillPath = p.setExtension(jsPath, '.dill');

      _logger.info('Generating js and full dill SDK files...');

      final args = <String>[
        sdkLayout.dartdevcSnapshotPath,
        '--compile-sdk',
        '--multi-root',
        sdkLayout.sdkDirectory,
        '--multi-root-scheme',
        'org-dartlang-sdk',
        '--libraries-file',
        'org-dartlang-sdk:///lib/libraries.json',
        '--modules',
        'amd',
        // Sound full dill file is included in the SDK,
        // we only create one for weak mode.
        // This creates full dill file in '$fullDillPath'.
        if (!hasFullDillAsset) '--summarize',
        if (soundNullSafety) '--sound-null-safety',
        if (!soundNullSafety) '--no-sound-null-safety',
        'dart:core',
        '-o',
        jsPath,
      ];

      _logger.fine('Executing dart ${args.join(' ')}');
      final process = await Process.start(Platform.resolvedExecutable, args,
          workingDirectory: sdkLayout.sdkDirectory);

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
          throw Exception('The Dart compiler exited unexpectedly '
              'while generating $jsPath');
        }
      });

      await _moveAndValidate(jsPath, outputJsPath);
      await _moveAndValidate(jsMapPath, outputJsMapPath);
      await _moveAndValidate(fullDillPath, outputFullDillPath);

      _logger.info('Done generating js and full dill SDK files.');
    } catch (e, s) {
      _logger.severe(
          'Failed to generate '
          'SDK js, source map, and full dill',
          e,
          s);
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
          ? p.join(outputDir.path, sdkLayout.sdkSummarySoundFileName)
          : p.join(outputDir.path, sdkLayout.sdkSummaryWeakFileName);

      _logger.info('Generating SDK summary files...');

      final args = <String>[
        sdkLayout.kernelWorkerSnapshotPath,
        '--target',
        'ddc',
        '--multi-root',
        sdkLayout.sdkDirectory,
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

      _logger.fine('Executing dart ${args.join(' ')}');
      final process = await Process.start(Platform.resolvedExecutable, args,
          workingDirectory: sdkLayout.sdkDirectory);

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
          throw Exception('The Dart kernel worker exited unexpectedly '
              'while generating $summaryPath');
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

  Future<void> _moveAndValidate(String from, String to) async {
    if (!_exists(to)) {
      _logger.fine('Renaming $from to $to');
      await fileSystem.file(from).rename(to);

      if (!_exists(to)) {
        _logger.severe('Failed to generate SDK asset at $to');
        throw Exception('File does not exist.');
      }
    }
  }
}
