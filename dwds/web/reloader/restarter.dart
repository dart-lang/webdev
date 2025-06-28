// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:js_interop';

abstract class Restarter {
  /// Attempts to perform a hot restart and returns whether it was successful or
  /// not.
  Future<bool> restart({String? runId, Future? readyToRunMain});

  /// After a previous call to [hotReloadStart], completes the hot
  /// reload by pushing the libraries into the Dart runtime.
  Future<void> hotReloadEnd();

  /// Computes the sources and libraries to reload, loads them into the page,
  /// and returns a map of module names to libraries using
  /// [hotReloadSourcesPath] as the path to a JSONified list of maps which
  /// follows the following format:
  ///
  /// ```json
  /// [
  ///   {
  ///     "src": "<file_name>",
  ///     "module": "<module_name>",
  ///     "libraries": ["<lib1>", "<lib2>"],
  ///   },
  /// ]
  /// ```
  ///
  /// `src`: A string that corresponds to the file path containing a DDC library
  /// bundle.
  /// `module`: The name of the library bundle in `src`.
  /// `libraries`: An array of strings containing the libraries that were
  /// compiled in `src`.
  Future<JSObject> hotReloadStart(String hotReloadSourcesPath);
}
