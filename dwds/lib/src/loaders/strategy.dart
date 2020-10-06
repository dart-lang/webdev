// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';

import '../../dwds.dart';
import '../utilities/shared.dart';

LoadStrategy _globalLoadStrategy;

set globalLoadStrategy(LoadStrategy strategy) => _globalLoadStrategy = strategy;

LoadStrategy get globalLoadStrategy {
  if (_globalLoadStrategy == null) {
    throw StateError('Global load strategy not set');
  }
  return _globalLoadStrategy;
}

abstract class LoadStrategy {
  final AssetReader _assetReader;
  final LogWriter _logWriter;

  LoadStrategy(this._assetReader, this._logWriter);

  /// The ID for this strategy.
  ///
  /// This ID is passed to the injected client so that it can react accordingly.
  String get id;

  /// Returns a snippet of JS code that loads all Dart libraries into a `libs`
  /// variable.
  String get loadLibrariesSnippet;

  /// Returns a snippet of JS code that can be used to load a JS module.
  ///
  /// The snippet should be a reference to a function that takes a single
  /// argument which is the module name to load.
  String get loadModuleSnippet;

  /// The reload configuration for this strategy, e.g. liveReload.
  ReloadConfiguration get reloadConfiguration;

  /// Returns a snippet of JS code that initializes a `library` variable that
  /// has the actual library object in DDC for [libraryUri].
  ///
  /// In DDC we have module libraries indexed by names of the form
  /// 'packages/package/mainFile' with no .dart suffix on the file, or
  /// 'directory/packageName/mainFile', also with no .dart suffix, and relative
  /// to the serving root, normally /web within the package. These modules have
  /// a map from the URI with a Dart-specific scheme
  /// (package: or org-dartlang-app:) to the library objects. The [libraryUri]
  /// parameter should be one of these Dart-specific scheme URIs, and we set
  /// `library` the corresponding library.
  String loadLibrarySnippet(String libraryUri) => '''
   var sdkUtils = $loadModuleSnippet('dart_sdk').dart;
   var library = sdkUtils.getLibrary('$libraryUri');
   if (!library) throw 'cannot find library for $libraryUri';
  ''';

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
  Future<String> moduleForServerPath(String entrypoint, String serverPath);

  /// Returns the server path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js
  ///
  Future<String> serverPathForModule(String entrypoint, String module);

  /// Returns the source map path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js.map
  ///
  Future<String> sourceMapPathForModule(String entrypoint, String module);

  /// Returns the server path for the app uri.
  ///
  /// For example:
  ///
  ///   org-dartlang-app://web/main.dart -> main.dart
  ///
  /// Will return `null` if the provided uri is not
  /// an app URI.
  String serverPathForAppUri(String appUri);

  final _providers = <String, MetadataProvider>{};

  MetadataProvider metadataProviderFor(String entrypoint) =>
      _providers[entrypoint];

  void initializeEntrypoint(String entrypoint) {
    var metadataProvider =
        MetadataProvider(entrypoint, _assetReader, _logWriter);
    _providers[metadataProvider.entrypoint] = metadataProvider;
  }
}

enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }
