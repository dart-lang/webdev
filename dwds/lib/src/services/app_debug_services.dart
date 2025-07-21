// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/dwds_vm_client.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart'
    show ChromeProxyService;
import 'package:dwds/src/services/debug_service.dart';

/// Common interface for debug service containers.
abstract class IAppDebugServices {
  IDebugService get debugService;
  dynamic get dwdsVmClient;
  dynamic get dwdsStats;
  Uri? get ddsUri;
  String? get connectedInstanceId;
  set connectedInstanceId(String? id);
  Future<void> close();
  dynamic get chromeProxyService;
  dynamic get webSocketProxyService;
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
  DwdsVmClient get dwdsVmClient => _dwdsVmClient;

  @override
  DwdsStats get dwdsStats => _dwdsStats;

  @override
  Uri? get ddsUri => _ddsUri;

  @override
  String? get connectedInstanceId => _connectedInstanceId;

  @override
  set connectedInstanceId(String? id) => _connectedInstanceId = id;

  @override
  ChromeProxyService get chromeProxyService =>
      debugService.chromeProxyService as ChromeProxyService;

  // WebSocket functionality not available in Chrome-based service
  @override
  dynamic get webSocketProxyService => null;

  @override
  Future<void> close() =>
      _closed ??= Future.wait([debugService.close(), dwdsVmClient.close()]);
}
