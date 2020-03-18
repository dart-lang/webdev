// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'services/chrome_proxy_service.dart' show ChromeProxyService;
import 'services/debug_service.dart';

final _logger = Logger('DwdsVmClient');

// A client of the vm service that registers some custom extensions like
// hotRestart.
class DwdsVmClient {
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object>> _responseController;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  DwdsVmClient(this.client, this._requestController, this._responseController);

  Future<void> close() => _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        client.dispose();
      }();

  static Future<DwdsVmClient> create(DebugService debugService) async {
    // Set up hot restart as an extension.
    var requestController = StreamController<Map<String, Object>>();
    var responseController = StreamController<Map<String, Object>>();
    VmServerConnection(requestController.stream, responseController.sink,
        debugService.serviceExtensionRegistry, debugService.chromeProxyService);
    var client =
        VmService(responseController.stream.map(jsonEncode), (request) {
      if (requestController.isClosed) {
        _logger.warning(
            'Attempted to send a request but the connection is closed:\n\n'
            '$request');
        return;
      }
      requestController.sink.add(jsonDecode(request) as Map<String, dynamic>);
    });
    var chromeProxyService =
        debugService.chromeProxyService as ChromeProxyService;

    client.registerServiceCallback('hotRestart', (request) async {
      await _disableBreakpointsAndResume(client, chromeProxyService);
      var context = await chromeProxyService.executionContext.id;
      try {
        await chromeProxyService.remoteDebugger
            .sendCommand('Runtime.evaluate', params: {
          'expression': r'$dartHotRestart();',
          'awaitPromise': true,
          'contextId': context,
        });
      } on WipError catch (exception) {
        var code = exception.error['code'];
        // This corresponds to `Execution context was destroyed` which can
        // occur during a hot restart that must fall back to a full reload.
        if (code != -32000) {
          return {
            'error': {
              'code': exception.error['code'],
              'message': exception.error['message'],
              'data': exception,
            }
          };
        }
      }
      // Only return success after the isolate has fully started.
      var stream = chromeProxyService.onEvent('Isolate');
      await stream.firstWhere((event) => event.kind == EventKind.kIsolateStart);
      return {'result': Success().toJson()};
    });
    await client.registerService('hotRestart', 'DWDS fullReload');

    client.registerServiceCallback('fullReload', (_) async {
      await chromeProxyService.remoteDebugger.enablePage();
      // TODO: use built in `page.reload` once it works,
      // https://github.com/google/webkit_inspection_protocol.dart/issues/44
      await chromeProxyService.remoteDebugger.sendCommand('Page.reload');
      return {'result': Success().toJson()};
    });
    await client.registerService('fullReload', 'DWDS');

    client.registerServiceCallback('ext.dwds.screenshot', (_) async {
      await chromeProxyService.remoteDebugger.enablePage();
      var response = await chromeProxyService.remoteDebugger
          .sendCommand('Page.captureScreenshot');
      return {'result': response.result};
    });
    await client.registerService('ext.dwds.screenshot', 'DWDS');

    return DwdsVmClient(client, requestController, responseController);
  }
}

Future<void> _disableBreakpointsAndResume(
    VmService client, ChromeProxyService chromeProxyService) async {
  var vm = await client.getVM();
  var isolateRef = vm.isolates.first;
  var isolate = await client.getIsolate(isolateRef.id);
  await chromeProxyService.disableBreakpoints();
  if (isolate.pauseEvent.kind == EventKind.kPauseInterrupted ||
      isolate.pauseEvent.kind == EventKind.kPauseBreakpoint) {
    await client.resume(isolate.id);
  }
}
