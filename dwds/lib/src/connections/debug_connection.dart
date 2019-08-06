// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:vm_service/vm_service.dart';

import '../services/app_debug_services.dart';

/// A debug connection between the application in the browser and DWDS.
///
/// Supports debugging your running application through the Dart VM Service
/// Protocol.
class DebugConnection {
  final AppDebugServices _appDebugServices;
  final _onDoneCompleter = Completer();

  DebugConnection(this._appDebugServices) {
    _appDebugServices.chromeProxyService.remoteDebugger.onClose.first.then((_) {
      close();
    });
  }

  /// The port of the host Dart VM Service.
  int get port => _appDebugServices.debugService.port;

  /// The websocket endpoint of the Dart VM Service.
  String get wsUri => _appDebugServices.debugService.wsUri;

  /// A client of the Dart VM Service with DWDS specific extensions.
  VmService get vmService => _appDebugServices.dwdsVmClient.client;

  Future<void> close() async {
    if (!_onDoneCompleter.isCompleted) _onDoneCompleter.complete();
    _appDebugServices.chromeProxyService.remoteDebugger.close();
    await _appDebugServices.close();
  }

  Future<void> get onDone => _onDoneCompleter.future;
}

/// [ChromeProxyService] of a [DebugConnection] for internal use only.
ChromeProxyService fetchChromeProxyService(DebugConnection debugConnection) =>
    debugConnection._appDebugServices.chromeProxyService;
