// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:dwds/src/debugging/dart_runtime_debugger.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

abstract class LoadStrategy {
  final AssetReader _assetReader;
  final String? _packageConfigPath;
  final _providers = <String, MetadataProvider>{};

  LoadStrategy(this._assetReader, {String? packageConfigPath})
    : _packageConfigPath = packageConfigPath ?? _findPackageConfigFilePath();

  /// The ID for this strategy.
  ///
  /// This ID is passed to the injected client so that it can react accordingly.
  String get id;

  /// Module format for JS generated by the compiler.
  ///
  /// Module format is passed to the expression compilation worker during
  /// expression evaluation.
  String get moduleFormat;

  /// Module containing code for loading libraries.
  ///
  /// Used for preventing stepping into the library loading code.
  String get loadLibrariesModule;

  /// Returns a snippet of JS code that can be used to load a JS module.
  ///
  /// The snippet should be a reference to a function that takes a single
  /// argument which is the module name to load.
  String get loadModuleSnippet;

  /// Provides a runtime debugger for the Dart runtime.
  DartRuntimeDebugger get dartRuntimeDebugger;

  /// The relative root path for library paths. The current directory will be
  /// used if this is not overridden.
  String? get libraryRoot => null;

  /// The reload configuration for this strategy, e.g. liveReload.
  ReloadConfiguration get reloadConfiguration;

  /// App build settings, such as entry point, build flags, app kind etc.
  BuildSettings get buildSettings;

  /// A handler for strategy specific requests.
  ///
  /// Used as a part of the injected_handler middleware.
  Handler get handler;

  /// Returns a loader to read the content of the package configuration.
  ///
  /// The package configuration URIs will be resolved relative to
  /// [packageConfigPath], but the loader can read the config from a different
  /// location.
  ///
  /// If null, the default loader will read from [packageConfigPath].
  Future<Uint8List?> Function(Uri uri)? get packageConfigLoader => null;

  /// The absolute path to the app's package configuration.
  String get packageConfigPath {
    return _packageConfigPath ?? _defaultPackageConfigPath;
  }

  /// The default package config path if none is provided.
  String get _defaultPackageConfigPath =>
      p.join(DartUri.currentDirectory, '.dart_tool', 'package_config.json');

  /// Returns the absolute file path of the `package_config.json` file in the `.dart_tool`
  /// directory, searching recursively from the current directory hierarchy.
  static String? _findPackageConfigFilePath() {
    var candidateDir = Directory(DartUri.currentDirectory).absolute;

    while (true) {
      final candidatePackageConfigFile = File(
        p.join(candidateDir.path, '.dart_tool', 'package_config.json'),
      );

      if (candidatePackageConfigFile.existsSync()) {
        return candidatePackageConfigFile.path;
      }

      final parentDir = candidateDir.parent;
      if (parentDir.path == candidateDir.path) {
        // We've reached the root directory
        return null;
      }

      candidateDir = parentDir;
    }
  }

  /// Returns the bootstrap required for this [LoadStrategy].
  ///
  /// The bootstrap is appended to the end of the entry point module.
  Future<String> bootstrapFor(String entrypoint);

  /// JS code snippet for loading the injected client script.
  String loadClientSnippet(String clientScript);

  /// Returns the module for the corresponding server path.
  ///
  /// For example:
  ///
  /// /packages/path/path.ddc.js -> packages/path/path
  ///
  Future<String?> moduleForServerPath(String entrypoint, String serverPath);

  /// Returns the server path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js
  ///
  Future<String?> serverPathForModule(String entrypoint, String module);

  /// Returns the source map path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js.map
  ///
  Future<String?> sourceMapPathForModule(String entrypoint, String module);

  /// Returns a map from module id to module info for the provided entrypoint.
  ///
  /// For example:
  ///
  ///   web/main -> {main.ddc.full.dill, main.ddc.dill}
  ///
  Future<Map<String, ModuleInfo>> moduleInfoForEntrypoint(String entrypoint);

  /// Returns the server path for the app uri.
  ///
  /// For example:
  ///
  ///   org-dartlang-app://web/main.dart -> main.dart
  ///
  /// Will return `null` if the provided uri is not
  /// an app URI.
  String? serverPathForAppUri(String appUri);

  /// Returns the relative path in google3, determined by the [absolutePath].
  ///
  /// Returns `null` if not a google3 app.
  String? g3RelativePath(String absolutePath);

  /// Returns the [MetadataProvider] for the application located at the provided
  /// [entrypoint].
  MetadataProvider metadataProviderFor(String entrypoint) {
    if (_providers.containsKey(entrypoint)) {
      return _providers[entrypoint]!;
    } else {
      throw StateError('No metadata provider for $entrypoint');
    }
  }

  /// Creates and returns a [MetadataProvider] with the given [entrypoint] and
  /// [reader].
  MetadataProvider createProvider(String entrypoint, AssetReader reader) =>
      MetadataProvider(entrypoint, reader, useModuleName: true);

  /// Initializes a [MetadataProvider] for the application located at the
  /// provided [entrypoint].
  Future<void> trackEntrypoint(String entrypoint) {
    final metadataProvider = createProvider(entrypoint, _assetReader);
    _providers[metadataProvider.entrypoint] = metadataProvider;
    // Returns a Future so that the asynchronous g3-implementation can override
    // this method:
    return Future.value();
  }
}

enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }

/// App build settings.
///
/// We use load strategy to determine the build settings for the app.
/// Note that some load strategies need to read those arguments from
/// the build metadata as they are not always available until the app
/// is built and loaded.
class BuildSettings {
  final Uri? appEntrypoint;
  final bool canaryFeatures;
  final bool isFlutterApp;
  final List<String> experiments;

  const BuildSettings({
    this.appEntrypoint,
    this.canaryFeatures = false,
    this.isFlutterApp = true,
    this.experiments = const <String>[],
  });
}
