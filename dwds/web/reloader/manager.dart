// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:dwds/data/isolate_events.dart';
import 'package:dwds/data/serializers.dart';
import 'package:sse/client/sse_client.dart';

import 'restarter.dart';

class ReloadingManager {
  final SseClient _client;
  final String _appId;
  final String _appInstanceId;
  final Restarter _restarter;

  ReloadingManager(
      this._client, this._appId, this._appInstanceId, this._restarter);

  /// Attemps to perform a hot restart and returns whether it was successful or
  /// not.
  Future<bool> hotRestart() async {
    _beforeRestart();
    var result = await _restarter.restart();
    _afterRestart();
    return result;
  }

  /// Does a hard reload of the application.
  void reloadPage() {
    window.location.reload();
  }

  void _afterRestart() {
    // Notify package:dwds that the isolate has been created.
    // package:dwds will respond with a [RunRequest].
    _client.sink.add(jsonEncode(serializers.serialize(IsolateStart((b) => b
      ..appId = _appId
      ..instanceId = _appInstanceId))));
  }

  void _beforeRestart() {
    // Notify package:dwds that the isolate is about to exit.
    _client.sink.add(jsonEncode(serializers.serialize(IsolateExit((b) => b
      ..appId = _appId
      ..instanceId = _appInstanceId))));
  }
}
