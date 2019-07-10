// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../service.dart';
import 'chrome_proxy_service.dart' show ChromeProxyService;
import 'dwds_vm_client.dart';

/// A container for all the services required for debugging an application.
class AppDebugServices {
  final DebugService debugService;
  final DwdsVmClient dwdsVmClient;

  ChromeProxyService get chromeProxyService =>
      debugService.chromeProxyService as ChromeProxyService;

  /// The instance ID for the currently connected application, if there is one.
  ///
  /// We only allow a given app to be debugged in a single tab at a time.
  String connectedInstanceId;

  AppDebugServices(this.debugService, this.dwdsVmClient);

  Future<void> close() =>
      Future.wait([debugService.close(), dwdsVmClient.close()]);
}
