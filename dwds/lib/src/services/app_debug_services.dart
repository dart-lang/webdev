// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/dwds_vm_client.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/services/proxy_service.dart';

/// Common interface for debug service containers.
abstract class AppDebugServices {
  DebugService get debugService;
  DwdsVmClient get dwdsVmClient;
  DwdsStats? get dwdsStats;
  Uri? get ddsUri;
  Uri? get devToolsUri;
  Uri? get dtdUri;
  String? get connectedInstanceId;
  set connectedInstanceId(String? id);
  Future<void> close();
  ProxyService get proxyService;
}

/// Chrome-based debug services container.
class ChromeAppDebugServices implements AppDebugServices {
  final ChromeDebugService _debugService;
  final ChromeDwdsVmClient _dwdsVmClient;
  final DwdsStats _dwdsStats;
  final Uri? _ddsUri;
  final Uri? _devToolsUri;
  final Uri? _dtdUri;
  Future<void>? _closed;
  String? _connectedInstanceId;

  ChromeAppDebugServices(
    this._debugService,
    this._dwdsVmClient,
    this._dwdsStats,
    this._ddsUri,
    this._devToolsUri,
    this._dtdUri,
  );

  @override
  ChromeDebugService get debugService => _debugService;

  @override
  DwdsVmClient get dwdsVmClient => _dwdsVmClient;

  @override
  DwdsStats get dwdsStats => _dwdsStats;

  @override
  Uri? get ddsUri => _ddsUri;

  @override
  Uri? get devToolsUri => _devToolsUri;

  @override
  Uri? get dtdUri => _dtdUri;

  @override
  String? get connectedInstanceId => _connectedInstanceId;

  @override
  set connectedInstanceId(String? id) => _connectedInstanceId = id;

  @override
  ProxyService get proxyService => debugService.chromeProxyService;

  @override
  Future<void> close() =>
      _closed ??= Future.wait([debugService.close(), dwdsVmClient.close()]);
}

/// WebSocket-based implementation of app debug services.
class WebSocketAppDebugServices implements AppDebugServices {
  final WebSocketDebugService _debugService;
  final WebSocketDwdsVmClient _dwdsVmClient;
  Future<void>? _closed;
  @override
  String? connectedInstanceId;

  WebSocketAppDebugServices(this._debugService, this._dwdsVmClient);

  @override
  WebSocketDebugService get debugService => _debugService;

  @override
  DwdsVmClient get dwdsVmClient => _dwdsVmClient;

  // WebSocket-only service - Chrome/DDS features not available
  @override
  DwdsStats? get dwdsStats => null;

  @override
  // TODO(bkonyi): DDS should still start in WebSocket mode.
  Uri? get ddsUri => null;

  @override
  Uri? get devToolsUri => null;

  @override
  Uri? get dtdUri => null;

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
