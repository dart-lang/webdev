// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

abstract class LoadStrategy {
  final AssetReader _assetReader;
  final String? _packageConfigPath;
  late MetadataProvider _provider;
  String? _appName;

  LoadStrategy(
    this._assetReader, {
    String? packageConfigPath,
  }) : _packageConfigPath = packageConfigPath;

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

  /// The reload configuration for this strategy, e.g. liveReload.
  ReloadConfiguration get reloadConfiguration;

  /// App build settings, such as entry point, build flags, app kind etc.
  BuildSettings get buildSettings;

  /// Returns the bootstrap required for this [LoadStrategy].
  ///
  /// The bootstrap is appended to the end of the entry point module.
  Future<String> bootstrapFor(String entrypoint);

  /// A handler for strategy specific requests.
  ///
  /// Used as a part of the injected_handler middleware.
  Handler get handler;

  /// JS code snippet for loading the injected client script.
  String loadClientSnippet(String clientScript);

  /// Returns the module for the corresponding server path.
  ///
  /// For example:
  ///
  /// /packages/path/path.ddc.js -> packages/path/path
  ///
  Future<String?> moduleForServerPath(String appName, String serverPath);

  /// Returns the server path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js
  ///
  Future<String?> serverPathForModule(String appName, String module);

  /// Returns the source map path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js.map
  ///
  Future<String?> sourceMapPathForModule(String appName, String module);

  /// Returns a map from module id to module info for the provided entrypoint.
  ///
  /// For example:
  ///
  ///   web/main -> {main.ddc.full.dill, main.ddc.dill}
  ///
  Future<Map<String, ModuleInfo>> moduleInfoFor(String appName);

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

  /// The absolute path to the app's package configuration.
  String get packageConfigPath {
    return _packageConfigPath ?? _defaultPackageConfigPath;
  }

  /// The default package config path if none is provided.
  String get _defaultPackageConfigPath => p.join(
        DartUri.currentDirectory,
        '.dart_tool',
        'package_config.json',
      );

  /// Returns the [MetadataProvider] for the application [appName].
  ///
  /// Note: We  only support one app debugging at a time, so the
  /// [appName] is currently ignored.
  ///
  /// TODO(annagrin): Support multi-app debugging.
  /// Issue: https://github.com/dart-lang/webdev/issues/1769
  MetadataProvider metadataProviderFor(String? appName) => _provider;

  /// Initializes a [MetadataProvider] for the application located at the
  /// provided main [entrypoint].
  ///
  /// Currently we don't have a way to detect an app name at this stage
  /// so we only support one app debugging at a time, with lazy-compilation
  /// sub-apps allowed.
  ///
  /// TODO(annagrin): Support multi-app debugging.
  /// Issue: https://github.com/dart-lang/webdev/issues/1769
  Future<void> trackAppEntrypoint(String entrypoint) async {
    _provider = MetadataProvider(_assetReader)..update(entrypoint);

    // Some implementers need to do more work.
    // Make sure we always await on the result.
    return Future<void>.value();
  }

  /// Initializes a [MetadataProvider] for the sub-application of [appName]
  /// located at the provided [entrypoint].
  ///
  /// TODO(annagrin): Support multi-app debugging.
  /// Issue: https://github.com/dart-lang/webdev/issues/1769
  void trackEntrypoint(String appName, String entrypoint) {
    _appName ??= appName;
    if (_appName != appName) {
      throw StateError('Multi-app debugging is not supported yet');
    }
    _provider.update(entrypoint);
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
