// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:dwds/service.dart';

import '../../serve/chrome.dart';
import '../debugger/webdev_vm_client.dart';

/// A container for all the services required for debugging an application.
class AppDebugServices {
  final Chrome chrome;
  final DebugService debugService;
  final WebdevVmClient webdevClient;

  /// The instance ID for the currently connected application, if there is one.
  ///
  /// We only allow a given app to be debugged in a single tab at a time.
  String connectedInstanceId;

  AppDebugServices(this.chrome, this.debugService, this.webdevClient);

  Future<void> close() =>
      Future.wait([debugService.close(), webdevClient.close()]);
}
