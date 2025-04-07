// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:js_interop';

abstract class Restarter {
  /// Attempts to perform a hot restart and returns whether it was successful or
  /// not.
  Future<bool> restart({String? runId, Future? readyToRunMain});

  /// Performs a hot reload using the sources and libraries computes in the
  /// previous call to [fetchLibrariesForHotReload].
  Future<void> reload();

  /// Computes the sources and libraries to reload and returns the list of
  /// libraries using [hotReloadSourcesPath] as the path to a JSONified list of
  /// maps which follows the following format:
  ///
  /// ```json
  /// [
  ///   {
  ///     "src": "<file_name>",
  ///     "libraries": ["<lib1>", "<lib2>"],
  ///   },
  /// ]
  /// ```
  ///
  /// `src`: A string that corresponds to the file path containing a DDC library
  /// bundle.
  /// `libraries`: An array of strings containing the libraries that were
  /// compiled in `src`.
  Future<JSArray<JSString>> fetchLibrariesForHotReload(
    String hotReloadSourcesPath,
  );
}
