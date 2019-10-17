// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:sse/server/sse_handler.dart';

import '../../data/connect_request.dart';
import '../../data/run_request.dart';
import '../../data/serializers.dart';

/// A connection between the application loaded in the browser and DWDS.
class AppConnection {
  /// The initial connection request sent from the application in the browser.
  final ConnectRequest request;
  final _startCompleter = Completer();
  final SseConnection _connection;

  AppConnection(this.request, this._connection);

  bool get isStarted => _startCompleter.isCompleted;
  Future<void> get onStart => _startCompleter.future;

  void runMain() {
    if (_startCompleter.isCompleted) {
      throw StateError('Main has already started.');
    }
    _connection.sink.add(jsonEncode(serializers.serialize(RunRequest())));
    _startCompleter.complete();
  }
}
