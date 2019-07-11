// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

import 'src/services/app_debug_services.dart';

/// A debug connection between the application in the browser and DWDS.
class DebugConnection {
  final AppDebugServices _appDebugServices;
  final _onDoneCompleter = Completer();

  DebugConnection(this._appDebugServices) {
    _appDebugServices.chromeProxyService.tabConnection.onClose.first.then((_) {
      close();
    });
  }

  int get port => _appDebugServices.debugService.port;

  String get wsUri => _appDebugServices.debugService.wsUri;

  VmService get vmService => _appDebugServices.dwdsVmClient.client;

  Future<void> close() async {
    if (!_onDoneCompleter.isCompleted) _onDoneCompleter.complete();
    await _appDebugServices.chromeProxyService.tabConnection.close();
    await _appDebugServices.close();
  }

  Future<void> get onDone => _onDoneCompleter.future;
}
