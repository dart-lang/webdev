// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:sse/server/sse_handler.dart';

import 'data/connect_request.dart';
import 'data/run_request.dart';
import 'data/serializers.dart';

/// A connection between the application loaded in the browser and DWDS.
class AppConnection {
  final ConnectRequest request;
  final SseConnection _connection;

  var _isStarted = false;

  AppConnection(this.request, this._connection);

  void runMain() {
    if (!_isStarted) {
      _connection.sink.add(jsonEncode(serializers.serialize(RunRequest())));
    }
    _isStarted = true;
  }
}
