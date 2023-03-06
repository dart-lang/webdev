// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';

final _logger = Logger('DwdsVmClient');

// A client of the vm service that registers some custom extensions like
// hotRestart.
class DwdsVmClient {
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object?>> _responseController;

  static const int kFeatureDisabled = 100;
  static const String kFeatureDisabledMessage = 'Feature is disabled.';

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  DwdsVmClient(this.client, this._requestController, this._responseController);

  Future<void> close() => _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
      }();

  static Future<DwdsVmClient> create(
      DebugService debugService, DwdsStats dwdsStats) async {
    // Set up hot restart as an extension.
    final requestController = StreamController<Map<String, Object>>();
    final responseController = StreamController<Map<String, Object?>>();
    VmServerConnection(requestController.stream, responseController.sink,
        debugService.serviceExtensionRegistry, debugService.chromeProxyService);
    final client =
        VmService(responseController.stream.map(jsonEncode), (request) {
      if (requestController.isClosed) {
        _logger.warning(
            'Attempted to send a request but the connection is closed:\n\n'
            '$request');
        return;
      }
      requestController.sink.add(Map<String, Object>.from(jsonDecode(request)));
    });
    final chromeProxyService =
        debugService.chromeProxyService as ChromeProxyService;

    final dwdsVmClient =
        DwdsVmClient(client, requestController, responseController);

    // Register '_flutter.listViews' method on the chrome proxy service vm.
    // In native world, this method is provided by the engine, but the web
    // engine is not aware of the VM uri or the isolates.
    //
    // Issue: https://github.com/dart-lang/webdev/issues/1315
    client.registerServiceCallback('_flutter.listViews', (request) async {
      final vm = await chromeProxyService.getVM();
      final isolates = vm.isolates;
      return <String, dynamic>{
        'result': <String, Object>{
          'views': <Object>[
            for (var isolate in isolates ?? [])
              <String, Object>{
                'id': isolate.id,
                'isolate': isolate.toJson(),
              }
          ],
        }
      };
    });
    await client.registerService('_flutter.listViews', 'DWDS');

    client.registerServiceCallback(
        'hotRestart',
        (request) => captureElapsedTime(
              chromeProxyService.hotRestart,
              (_) => DwdsEvent.hotRestart(),
            ));
    await client.registerService('hotRestart', 'DWDS');

    client.registerServiceCallback(
        'fullReload',
        (request) => captureElapsedTime(
              chromeProxyService.fullReload,
              (_) => DwdsEvent.fullReload(),
            ));
    await client.registerService('fullReload', 'DWDS');

    client.registerServiceCallback('ext.dwds.screenshot', (_) async {
      await chromeProxyService.remoteDebugger.enablePage();
      final response = await chromeProxyService.remoteDebugger
          .sendCommand('Page.captureScreenshot');
      return {'result': response.result};
    });
    await client.registerService('ext.dwds.screenshot', 'DWDS');

    client.registerServiceCallback('ext.dwds.sendEvent', (event) async {
      _processSendEvent(event, dwdsStats);
      return {'result': Success().toJson()};
    });
    await client.registerService('ext.dwds.sendEvent', 'DWDS');

    client.registerServiceCallback('ext.dwds.emitEvent', (event) async {
      emitEvent(DwdsEvent(
          event['type'] as String, event['payload'] as Map<String, dynamic>));
      return {'result': Success().toJson()};
    });
    await client.registerService('ext.dwds.emitEvent', 'DWDS');

    client.registerServiceCallback('_yieldControlToDDS', (request) async {
      final ddsUri = request['uri'] as String?;
      if (ddsUri == null) {
        return RPCError(
          request['method'] as String,
          RPCError.kInvalidParams,
          "'Missing parameter: 'uri'",
        ).toMap();
      }
      return DebugService.yieldControlToDDS(ddsUri)
          ? {'result': Success().toJson()}
          : {
              'error': {
                'code': kFeatureDisabled,
                'message': kFeatureDisabledMessage,
                'data':
                    'Existing VM service clients prevent DDS from taking control.',
              },
            };
    });
    await client.registerService('_yieldControlToDDS', 'DWDS');

    return dwdsVmClient;
  }
}

void _processSendEvent(Map<String, dynamic> event, DwdsStats dwdsStats) {
  final type = event['type'] as String?;
  final payload = event['payload'] as Map<String, dynamic>?;
  switch (type) {
    case 'DevtoolsEvent':
      {
        _logger.finest('Received DevTools event: $event');
        final action = payload?['action'] as String?;
        final screen = payload?['screen'] as String?;
        if (screen != null && action == 'pageReady') {
          _recordDwdsStats(dwdsStats, screen);
        } else {
          _logger.finest('Ignoring unknown event: $event');
        }
      }
  }
}

void _recordDwdsStats(DwdsStats dwdsStats, String screen) {
  if (dwdsStats.isFirstDebuggerReady) {
    final devToolsStart = dwdsStats.devToolsStart;
    final debuggerStart = dwdsStats.debuggerStart;
    if (devToolsStart != null) {
      final devToolLoadTime =
          DateTime.now().difference(devToolsStart).inMilliseconds;
      emitEvent(DwdsEvent.devToolsLoad(devToolLoadTime, screen));
      _logger.fine('DevTools load time: $devToolLoadTime ms');
    }
    if (debuggerStart != null) {
      final debuggerReadyTime =
          DateTime.now().difference(debuggerStart).inMilliseconds;
      emitEvent(DwdsEvent.debuggerReady(debuggerReadyTime, screen));
      _logger.fine('Debugger ready time: $debuggerReadyTime ms');
    }
  } else {
    _logger.finest('Debugger and DevTools stats are already recorded.');
  }
}
