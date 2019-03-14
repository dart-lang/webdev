// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/service.dart';
import 'package:pedantic/pedantic.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

// A client of the vm service that registers some custom extensions like
// hotRestart.
class WebdevVmClient {
  final VmService _client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object>> _responseController;

  WebdevVmClient(
      this._client, this._requestController, this._responseController);

  Future<void> close() async {
    await _requestController.close();
    await _responseController.close();
    _client.dispose();
  }

  static Future<WebdevVmClient> create(DebugService debugService) async {
    // Set up hot restart as an extension.
    var requestController = StreamController<Map<String, Object>>();
    var responseController = StreamController<Map<String, Object>>();
    VmServerConnection(requestController.stream, responseController.sink,
        debugService.serviceExtensionRegistry, debugService.chromeProxyService);
    var client = VmService(
        responseController.stream.map(jsonEncode),
        (request) => requestController.sink
            .add(jsonDecode(request) as Map<String, dynamic>));
    client.registerServiceCallback('hotRestart', (request) async {
      debugService.chromeProxyService.destroyIsolate();
      await debugService.chromeProxyService.tabConnection.runtime.sendCommand(
          'Runtime.evaluate',
          params: {'expression': r'$dartHotRestart();', 'awaitPromise': true});
      unawaited(debugService.chromeProxyService.createIsolate());
      return {'result': Success().toJson()};
    });
    await client.registerService('hotRestart', 'WebDev');

    // TODO: Remove this (we don't actually support it yet) once devtools
    // has published a new version.
    client.registerServiceCallback('reloadSources', (request) async {
      throw UnsupportedError(
          'Hot Reload is not yet supported for flutter web, try hot restart.');
    });
    await client.registerService('reloadSources', 'WebDev');

    return WebdevVmClient(client, requestController, responseController);
  }
}
