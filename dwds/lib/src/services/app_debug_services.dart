// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/dwds_vm_client.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart'
    show ChromeProxyService;
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/services/proxy_service.dart';

/// Common interface for debug service containers.
abstract class IAppDebugServices {
  IDebugService get debugService;
  IDwdsVmClient get dwdsVmClient;
  DwdsStats? get dwdsStats;
  Uri? get ddsUri;
  String? get connectedInstanceId;
  set connectedInstanceId(String? id);
  Future<void> close();
  ProxyService get proxyService;
}

/// Chrome-based debug services container.
class AppDebugServices implements IAppDebugServices {
  final DebugService _debugService;
  final DwdsVmClient _dwdsVmClient;
  final DwdsStats _dwdsStats;
  final Uri? _ddsUri;
  Future<void>? _closed;
  String? _connectedInstanceId;

  AppDebugServices(
    this._debugService,
    this._dwdsVmClient,
    this._dwdsStats,
    this._ddsUri,
  );

  @override
  DebugService get debugService => _debugService;

  @override
  IDwdsVmClient get dwdsVmClient => _dwdsVmClient;

  @override
  DwdsStats get dwdsStats => _dwdsStats;

  @override
  Uri? get ddsUri => _ddsUri;

  @override
  String? get connectedInstanceId => _connectedInstanceId;

  @override
  set connectedInstanceId(String? id) => _connectedInstanceId = id;

  @override
  ProxyService get proxyService =>
      debugService.chromeProxyService as ChromeProxyService;

  @override
  Future<void> close() =>
      _closed ??= Future.wait([debugService.close(), dwdsVmClient.close()]);
}

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
  IDwdsVmClient get dwdsVmClient => _dwdsVmClient;

  @override
  String? get connectedInstanceId => _connectedInstanceId;

  @override
  set connectedInstanceId(String? id) => _connectedInstanceId = id;

  // WebSocket-only service - Chrome/DDS features not available
  @override
  DwdsStats? get dwdsStats => null;
  @override
  Uri? get ddsUri => null;

  @override
  ProxyService get proxyService => _debugService.webSocketProxyService;

  @override
  Future<void> close() {
    return _closed ??= Future.wait([
      debugService.close(),
      dwdsVmClient.close(),
    ]);
  }
}
