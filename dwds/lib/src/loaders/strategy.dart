// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

LoadStrategy _globalLoadStrategy;

set globalLoadStrategy(LoadStrategy strategy) => _globalLoadStrategy = strategy;

LoadStrategy get globalLoadStrategy {
  if (_globalLoadStrategy == null) {
    throw StateError('Global load strategy not set');
  }
  return _globalLoadStrategy;
}

abstract class LoadStrategy {
  /// The ID for this strategy.
  ///
  /// This ID is passed to the injected client so that it can react accordingly.
  String get id;

  /// Returns a snippet of JS code that synchronously imports all Dart
  /// libraries using the DDC import functionality.
  String get importLibrariesSnippet;

  /// Returns a snippet of JS code that loads all Dart libraries into a `libs`
  /// variable.
  String get loadLibrariesSnippet => '$importLibrariesSnippet\n'
      'let libs = $loadModuleSnippet("dart_sdk").dart.getLibraries();\n';

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
}

enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }
