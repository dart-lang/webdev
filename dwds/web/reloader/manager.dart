// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:js_interop';

import 'package:dwds/data/isolate_events.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/sockets.dart';
import 'package:web/web.dart';

import 'ddc_library_bundle_restarter.dart';
import 'restarter.dart';

class ReloadingManager {
  final SocketClient _client;
  final Restarter _restarter;

  ReloadingManager(this._client, this._restarter);

  /// Attempts to perform a hot restart and returns whether it was successful or
  /// not.
  ///
  /// [runId] is used to hot restart code in the browser for all apps that
  /// - are loaded on the same page
  /// - called hotRestart with the same runId
  ///
  /// The apps are restarted at the same time on the first call.
  Future<bool> hotRestart({String? runId, Future? readyToRunMain}) async {
    _beforeRestart();
    final result = await _restarter.restart(
      runId: runId,
      readyToRunMain: readyToRunMain,
    );
    _afterRestart(result);
    return result;
  }

  /// After a previous call to [hotReloadStart], completes the hot
  /// reload by pushing the libraries into the Dart runtime.
  Future<void> hotReloadEnd() async {
    await _restarter.hotReloadEnd();
  }

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
  Future<JSObject> hotReloadStart(String hotReloadSourcesPath) =>
      _restarter.hotReloadStart(hotReloadSourcesPath);

  /// Does a hard reload of the application.
  void reloadPage() {
    window.location.reload();
  }

  /// Handles service extension requests by delegating to the appropriate restarter
  Future<Map<String, dynamic>?> handleServiceExtension(
    String method,
    Map<String, dynamic> args,
  ) async {
    final restarter = _restarter;
    if (restarter is DdcLibraryBundleRestarter) {
      return await restarter.handleServiceExtension(method, args);
    }
    // For other restarter types, return null to indicate not supported
    return null;
  }

  void _afterRestart(bool succeeded) {
    if (!succeeded) return;
    // Notify package:dwds that the isolate has been created.
    // package:dwds will respond with a [RunRequest].
    _client.sink.add(jsonEncode(serializers.serialize(IsolateStart())));
  }

  void _beforeRestart() {
    // Notify package:dwds that the isolate is about to exit.
    _client.sink.add(jsonEncode(serializers.serialize(IsolateExit())));
  }
}
