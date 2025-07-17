// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:dwds/src/services/app_debug_services.dart';
import 'package:dwds/src/services/web_socket_debug_service.dart';
import 'package:dwds/src/web_socket_dwds_vm_client.dart';

/// WebSocket-based implementation of app debug services.
class WebSocketAppDebugServices implements IAppDebugServices {
  final WebSocketDebugService _debugService;
  final WebSocketDwdsVmClient _dwdsVmClient;
  Future<void>? _closed;
  String? _connectedInstanceId;

  WebSocketAppDebugServices(this._debugService, this._dwdsVmClient);

  @override
  WebSocketDebugService get debugService => _debugService;

  @override
  WebSocketDwdsVmClient get dwdsVmClient => _dwdsVmClient;

  @override
  String? get connectedInstanceId => _connectedInstanceId;

  @override
  set connectedInstanceId(String? id) => _connectedInstanceId = id;

  // WebSocket-only service - Chrome/DDS features not available
  @override
  dynamic get dwdsStats => null;
  @override
  Uri? get ddsUri => null;
  @override
  dynamic get chromeProxyService =>
      throw UnsupportedError(
        'Chrome proxy service not available in WebSocket-only mode',
      );

  @override
  dynamic get webSocketProxyService => _debugService.webSocketProxyService;
  @override
  Future<void> close() {
    return _closed ??= Future.wait([
      debugService.close(),
      dwdsVmClient.close(),
    ]);
  }
}
