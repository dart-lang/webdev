// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/services/web_socket_proxy_service.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service_interface/vm_service_interface.dart';

final _logger = Logger('WebSocketDwdsVmClient');

typedef VmRequest = Map<String, Object>;
typedef VmResponse = Map<String, Object?>;

enum _NamespacedServiceExtension {
  extDwdsEmitEvent(method: 'ext.dwds.emitEvent'),
  extDwdsReload(method: 'ext.dwds.reload'),
  extDwdsRestart(method: 'ext.dwds.restart'),
  extDwdsScreenshot(method: 'ext.dwds.screenshot'),
  extDwdsSendEvent(method: 'ext.dwds.sendEvent'),
  flutterListViews(method: '_flutter.listViews');

  const _NamespacedServiceExtension({required this.method});
  final String method;
}

/// WebSocket-based DWDS VM client.
class WebSocketDwdsVmClient {
  final VmService client;
  final StreamController<VmRequest> _requestController;
  final StreamController<VmResponse> _responseController;
  Future<void>? _closed;

  WebSocketDwdsVmClient(
    this.client,
    this._requestController,
    this._responseController,
  );

  Future<void> close() =>
      _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
      }();

  static Future<WebSocketDwdsVmClient> create(
    WebSocketDebugService debugService,
  ) async {
    _logger.fine('Creating WebSocket DWDS VM client');
    final webSocketProxyService = debugService.webSocketProxyService;
    final responseController = StreamController<VmResponse>();
    final responseSink = responseController.sink;
    final responseStream = responseController.stream.asBroadcastStream();
    final requestController = StreamController<VmRequest>();
    final requestSink = requestController.sink;
    final requestStream = requestController.stream;

    _setUpVmServerConnection(
      webSocketProxyService: webSocketProxyService,
      debugService: debugService,
      responseStream: responseStream,
      responseSink: responseSink,
      requestStream: requestStream,
      requestSink: requestSink,
    );

    final client = _setUpVmClient(
      responseStream: responseStream,
      requestController: requestController,
      requestSink: requestSink,
    );

    _logger.fine('WebSocket DWDS VM client created successfully');
    return WebSocketDwdsVmClient(client, requestController, responseController);
  }

  static VmService _setUpVmClient({
    required Stream<VmResponse> responseStream,
    required StreamSink<VmRequest> requestSink,
    required StreamController<VmRequest> requestController,
  }) {
    final client = VmService(responseStream.map(jsonEncode), (request) {
      if (requestController.isClosed) {
        _logger.warning(
          'Attempted to send a request but the connection is closed:\n\n$request',
        );
        return;
      }
      requestSink.add(Map<String, Object>.from(jsonDecode(request)));
    });
    return client;
  }

  static void _setUpVmServerConnection({
    required WebSocketProxyService webSocketProxyService,
    required WebSocketDebugService debugService,
    required Stream<VmResponse> responseStream,
    required StreamSink<VmResponse> responseSink,
    required Stream<VmRequest> requestStream,
    required StreamSink<VmRequest> requestSink,
  }) {
    responseStream.listen((request) async {
      final response = await _maybeHandleServiceExtensionRequest(
        request,
        webSocketProxyService: webSocketProxyService,
      );
      if (response != null) {
        requestSink.add(response);
      }
    });

    final vmServerConnection = VmServerConnection(
      requestStream,
      responseSink,
      debugService.serviceExtensionRegistry,
      webSocketProxyService,
    );

    // Register service extensions
    for (final extension in _NamespacedServiceExtension.values) {
      _logger.finest('Registering service extension: ${extension.method}');
      debugService.serviceExtensionRegistry.registerExtension(
        extension.method,
        vmServerConnection,
      );
    }
  }

  static Future<VmRequest?> _maybeHandleServiceExtensionRequest(
    VmResponse request, {
    required WebSocketProxyService webSocketProxyService,
  }) async {
    VmRequest? response;
    final method = request['method'];

    _logger.finest('Processing service extension method: $method');

    if (method == _NamespacedServiceExtension.flutterListViews.method) {
      response = await _flutterListViewsHandler(webSocketProxyService);
    } else if (method == _NamespacedServiceExtension.extDwdsEmitEvent.method) {
      response = _extDwdsEmitEventHandler(request);
    } else if (method == _NamespacedServiceExtension.extDwdsReload.method) {
      response = {'result': 'Reload not implemented'};
    } else if (method == _NamespacedServiceExtension.extDwdsSendEvent.method) {
      response = _extDwdsSendEventHandler(request);
    } else if (method == _NamespacedServiceExtension.extDwdsScreenshot.method) {
      response = {'result': 'Screenshot not implemented'};
    }

    if (response != null) {
      response['id'] = request['id'] as String;
      response['jsonrpc'] = '2.0';
    }
    return response;
  }

  static Future<Map<String, Object>> _flutterListViewsHandler(
    WebSocketProxyService webSocketProxyService,
  ) async {
    final vm = await webSocketProxyService.getVM();
    _logger.finest('Retrieved VM with ${vm.isolates?.length ?? 0} isolates');
    final isolates = vm.isolates;
    return <String, Object>{
      'result': <String, Object>{
        'views': <Object>[
          for (final isolate in isolates ?? [])
            <String, Object>{'id': isolate.id, 'isolate': isolate.toJson()},
        ],
      },
    };
  }

  static Map<String, Object> _extDwdsEmitEventHandler(VmResponse request) {
    final event = request['params'] as Map<String, dynamic>?;
    if (event != null) {
      final type = event['type'] as String?;
      final payload = event['payload'] as Map<String, dynamic>?;
      if (type != null && payload != null) {
        _logger.fine('EmitEvent: $type $payload');
      }
    }
    return {'result': 'EmitEvent handled'};
  }

  static Map<String, Object> _extDwdsSendEventHandler(VmResponse request) {
    _logger.fine('SendEvent: $request');
    return {'result': 'SendEvent handled'};
  }
}
