// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.



import 'dart:async';

import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/handlers/socket_connections.dart';
import 'package:dwds/src/loaders/require.dart';
import 'package:dwds/src/loaders/strategy.dart';

/// A library of fake/stub implementations of our classes and their supporting
/// classes (e.g. WipConnection) for unit testing.
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger_data.dart';


class FakeSseConnection implements SseSocketConnection {
  /// A [StreamController] for incoming messages on SSE connection.
  final controllerIncoming = StreamController<String>();

  /// A [StreamController] for outgoing messages on SSE connection.
  final controllerOutgoing = StreamController<String>();

  @override
  bool get isInKeepAlivePeriod => false;

  @override
  StreamSink<String> get sink => controllerOutgoing.sink;

  @override
  Stream<String> get stream => controllerIncoming.stream;

  @override
  void shutdown() {}
}

class FakeModules implements Modules {
  @override
  void initialize(String entrypoint) {}

  @override
  Future<Uri> libraryForSource(String serverPath) {
    throw UnimplementedError();
  }

  @override
  Future<String> moduleForSource(String serverPath) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, String>> modules() {
    throw UnimplementedError();
  }

  @override
  Future<String> moduleForlibrary(String libraryUri) {
    throw UnimplementedError();
  }
}

/// Fake execution context that is needed for id only
class FakeExecutionContext extends ExecutionContext {
  @override
  Future<int> get id async {
    return 0;
  }

  FakeExecutionContext();
}
