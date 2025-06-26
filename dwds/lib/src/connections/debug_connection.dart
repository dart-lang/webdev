// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/src/services/app_debug_services.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:vm_service/vm_service.dart';

/// A debug connection between the application in the browser and DWDS.
///
/// Supports debugging your running application through the Dart VM Service
/// Protocol.
class DebugConnection {
  final IAppDebugServices _appDebugServices;
  final _onDoneCompleter = Completer();

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  DebugConnection(this._appDebugServices) {
    _setupChromeCloseHandler();
  }

  /// Sets up Chrome remote debugger close handler if available.
  void _setupChromeCloseHandler() {
    try {
      final chromeProxyService = _appDebugServices.chromeProxyService;
      if (chromeProxyService != null) {
        final remoteDebugger = chromeProxyService.remoteDebugger;
        remoteDebugger.onClose.first.then((_) => close());
      }
    } catch (_) {
      // Chrome proxy service not available in WebSocket-only mode - ignore
    }
  }

  /// The port of the host Dart VM Service.
  int get port => _appDebugServices.debugService.port;

  /// The endpoint of the Dart VM Service.
  String get uri => _appDebugServices.debugService.uri;

  // The endpoint of the Dart Development Service (DDS).
  String? get ddsUri => _appDebugServices.ddsUri?.toString();

  /// A client of the Dart VM Service with DWDS specific extensions.
  VmService get vmService => _appDebugServices.dwdsVmClient.client;

  Future<void> close() =>
      _closed ??= () async {
        // Close Chrome remote debugger if available
        try {
          final chromeProxyService = _appDebugServices.chromeProxyService;
          if (chromeProxyService != null) {
            await chromeProxyService.remoteDebugger.close();
          }
        } catch (_) {
          // Chrome proxy service not available in WebSocket-only mode - ignore
        }

        await _appDebugServices.close();
        _onDoneCompleter.complete();
      }();

  Future<void> get onDone => _onDoneCompleter.future;
}

/// [ChromeProxyService] of a [DebugConnection] for internal use only.
ChromeProxyService fetchChromeProxyService(DebugConnection debugConnection) =>
    debugConnection._appDebugServices.chromeProxyService;
