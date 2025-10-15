// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:vm_service/vm_service.dart';

/// Provides information about the currently loaded program.
class WebSocketAppInspector extends AppInspector {
  /// Counter for generating unique isolate IDs across page refreshes
  static int _globalIsolateIdCounter = 0;

  WebSocketAppInspector(super.appConnection, super.isolate, super.root);

  static Future<WebSocketAppInspector> create(
    AppConnection appConnection,
    String root,
  ) async {
    final id = (++_globalIsolateIdCounter).toString();
    final time = DateTime.now().millisecondsSinceEpoch;
    final name = 'main()';
    final isolate = Isolate(
      id: id,
      number: id,
      name: name,
      startTime: time,
      runnable: true,
      pauseOnExit: false,
      pauseEvent: Event(
        kind: EventKind.kPauseStart,
        timestamp: time,
        isolate: IsolateRef(
          id: id,
          name: name,
          number: id,
          isSystemIsolate: false,
        ),
      ),
      livePorts: 0,
      libraries: [],
      breakpoints: [],
      isSystemIsolate: false,
      isolateFlags: [],
    )..extensionRPCs = [];
    final inspector = WebSocketAppInspector(appConnection, isolate, root);

    await inspector.initialize();
    return inspector;
  }

  @override
  Future<Set<String>> getExtensionRpcs() {
    // TODO: implement getExtensionRpcs
    throw UnimplementedError();
  }
}
