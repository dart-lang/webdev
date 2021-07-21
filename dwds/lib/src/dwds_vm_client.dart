// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'events.dart';
import 'services/chrome_proxy_service.dart' show ChromeProxyService;
import 'services/debug_service.dart';

final _logger = Logger('DwdsVmClient');

// A client of the vm service that registers some custom extensions like
// hotRestart.
class DwdsVmClient {
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object>> _responseController;

  static const int kFeatureDisabled = 100;
  static const String kFeatureDisabledMessage = 'Feature is disabled.';

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  DwdsVmClient(this.client, this._requestController, this._responseController);

  Future<void> close() => _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
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
            for (var isolate in isolates)
              <String, Object>{
                'id': isolate.id,
                'isolate': isolate.toJson(),
              }
          ],
        }
      };
    });
    await client.registerService('_flutter.listViews', 'DWDS listViews');

    client.registerServiceCallback('hotRestart', (request) async {
      _logger.info('Attempting a hot restart');

      chromeProxyService.terminatingIsolates = true;
      await _disableBreakpointsAndResume(client, chromeProxyService);
      int context;
      try {
        _logger.info('Attempting to get execution context ID.');
        context = await chromeProxyService.executionContext.id;
        _logger.info('Got execution context ID.');
      } on StateError catch (e) {
        // We couldn't find the execution context. `hotRestart` may have been
        // triggered in the middle of a full reload.
        return {
          'error': {
            'code': RPCError.kInternalError,
            'message': e.message,
          }
        };
      }
      // Start listening for isolate create events before issuing a hot
      // restart. Only return success after the isolate has fully started.
      var stream = chromeProxyService.onEvent('Isolate');
      try {
        _logger.info('Issuing \$dartHotRestart request.');
        await chromeProxyService.remoteDebugger
            .sendCommand('Runtime.evaluate', params: {
          'expression': r'$dartHotRestart();',
          'awaitPromise': true,
          'contextId': context,
        });
        _logger.info('\$dartHotRestart request complete.');
      } on WipError catch (exception) {
        var code = exception.error['code'];
        // This corresponds to `Execution context was destroyed` which can
        // occur during a hot restart that must fall back to a full reload.
        if (code != RPCError.kServerError) {
          return {
            'error': {
              'code': exception.error['code'],
              'message': exception.error['message'],
              'data': exception,
            }
          };
        }
      }

      _logger.info('Waiting for Isolate Start event.');
      await stream.firstWhere((event) => event.kind == EventKind.kIsolateStart);
      chromeProxyService.terminatingIsolates = false;

      _logger.info('Successful hot restart');
      return {'result': Success().toJson()};
    });
    await client.registerService('hotRestart', 'DWDS fullReload');

    client.registerServiceCallback('fullReload', (_) async {
      _logger.info('Attempting a full reload');
      await chromeProxyService.remoteDebugger.enablePage();
      await chromeProxyService.remoteDebugger.pageReload();
      _logger.info('Successful full reload');
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

    client.registerServiceCallback('ext.dwds.emitEvent', (event) async {
      emitEvent(DwdsEvent(
          event['type'] as String, event['payload'] as Map<String, dynamic>));
      return {'result': Success().toJson()};
    });
    await client.registerService('ext.dwds.emitEvent', 'DWDS');

    client.registerServiceCallback('_yieldControlToDDS', (request) async {
      final ddsUri = request['uri'] as String;
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
                'details':
                    'Existing VM service clients prevent DDS from taking control.',
              },
            };
    });
    await client.registerService('_yieldControlToDDS', 'DWDS');

    return DwdsVmClient(client, requestController, responseController);
  }
}

Future<void> _disableBreakpointsAndResume(
    VmService client, ChromeProxyService chromeProxyService) async {
  _logger.info('Attempting to disable breakpoints and resume the isolate');
  var vm = await client.getVM();
  if (vm.isolates.isEmpty) throw StateError('No active isolate to resume.');
  var isolateRef = vm.isolates.first;

  // Pause the app to prevent it from hitting a breakpoint
  // during hot restart and stalling hot restart execution.
  // Then wait for the app to pause or to hit a breakpoint.
  var debug = chromeProxyService.onEvent('Debug').firstWhere((event) =>
      event.kind == EventKind.kPauseInterrupted ||
      event.kind == EventKind.kPauseBreakpoint);

  await client.pause(isolateRef.id);

  var isolate = await client.getIsolate(isolateRef.id);
  if (isolate.pauseEvent.kind != EventKind.kPauseInterrupted &&
      isolate.pauseEvent.kind != EventKind.kPauseBreakpoint) {
    await debug;
  }

  await chromeProxyService.disableBreakpoints();
  await client.resume(isolateRef.id);
  _logger.info('Successfully disabled breakpoints and resumed the isolate');
}
