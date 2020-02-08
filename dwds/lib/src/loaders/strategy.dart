// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

LoadStrategy globalLoadStrategy;

abstract class LoadStrategy {
  /// The ID for this strategy.
  String get id;

  /// Returns a snippet of JS code that imports all Dart libraries.
  String get importLibrariesSnippet;

  /// Returns a snippet of JS code that loads all Dart libraries into a `libs`
  /// variable.
  String get loadLibrariesSnippet => '$importLibrariesSnippet\n'
      'let libs = $loadModuleSnippet("dart_sdk").dart.getLibraries();\n';

  /// Returns a snippet of JS code that can be used to load a JS module.
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
