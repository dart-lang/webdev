// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library hot_reload_client;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/data/connect_request.dart';
import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/error_response.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/register_entrypoint_request.dart';
import 'package:dwds/data/register_event.dart';
import 'package:dwds/data/run_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/shared/batched_stream.dart';
import 'package:dwds/src/sockets.dart';
import 'package:js/js.dart';
import 'package:sse/client/sse_client.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'promise.dart';
import 'reloader/legacy_restarter.dart';
import 'reloader/manager.dart';
import 'reloader/require_restarter.dart';
import 'run_main.dart';

const _batchDelayMilliseconds = 1000;

// GENERATE:
// pub run build_runner build web
Future<void>? main() {
  return runZonedGuarded(() async {
    await runClient();
  }, (error, stackTrace) {
    print('''
Unhandled error detected in the injected client.js script.

You can disable this script in webdev by passing --no-injected-client if it
is preventing your app from loading, but note that this will also prevent
all debugging and hot reload/restart functionality from working.

The original error is below, please file an issue at
https://github.com/dart-lang/webdev/issues/new and attach this output:

$error
$stackTrace
''');
  });
}

Future<void> runClient() async {
  final appInfo = dartAppInfo..appInstanceId = const Uuid().v1();

  // used by tests and tools
  dartAppInstanceId = appInfo.appInstanceId;
  dartAppId = appInfo.appId;

  // used by require restarter
  loadModuleConfig = appInfo.loadModuleConfig;

  print(
      'Injected Client $dartAppInstanceId: Dart app info: ${appInfo.appName} ${appInfo.appId} ${appInfo.appInstanceId} ${appInfo.devHandlerPath} ${appInfo.moduleStrategy}');

  final connection = DevHandlerConnection(appInfo.devHandlerPath);

  registerEntrypoint = allowInterop((String appName, String entrypointPath) {
    if (appInfo.entrypoints.contains(entrypointPath)) return;
    appInfo.entrypoints.add(entrypointPath);

    if (_isChromium) {
      print(
          'Injected Client $dartAppInstanceId: sending registerEntrypoint request for $appName ($entrypointPath)');
      connection.sendRegisterEntrypointRequest(appName, entrypointPath);
    }
  });

  print('Injected Client $dartAppInstanceId: set registerEntrypoint');

  // Setup hot restart
  final restarter = switch (appInfo.moduleStrategy) {
    'require-js' => await RequireRestarter.create(),
    'legacy' => LegacyRestarter(),
    _ => throw StateError('Unknown module strategy: ${appInfo.moduleStrategy}'),
  };
  final manager = ReloadingManager(connection.client, restarter);
  hotRestartJs = allowInterop((String runId) {
    return toPromise(manager.hotRestart(runId: runId));
  });

  // Setup debug events
  emitDebugEvent = allowInterop((String kind, String eventData) {
    if (appInfo.emitDebugEvents) {
      connection.sendDebugEvent(kind, eventData);
    }
  });

  // Setup registerExtension events
  emitRegisterEvent = allowInterop(connection.sendRegisterEvent);

  // setup launching devtools
  launchDevToolsJs = allowInterop(() {
    if (!_isChromium) {
      window.alert(
        'Dart DevTools is only supported on Chromium based browsers.',
      );
      return;
    }
    connection.sendDevToolsRequest(appInfo.appId, appInfo.appInstanceId);
  });

  // Listen to commands from dwds dev handler
  connection.client.stream.listen(
    (serialized) async {
      final event = serializers.deserialize(jsonDecode(serialized));
      if (event is BuildResult) {
        if (appInfo.reloadConfiguration == 'ReloadConfiguration.liveReload') {
          manager.reloadPage();
        } else if (appInfo.reloadConfiguration ==
            'ReloadConfiguration.hotRestart') {
          await manager.hotRestart();
        } else if (appInfo.reloadConfiguration ==
            'ReloadConfiguration.hotReload') {
          print('Hot reload is currently unsupported. Ignoring change.');
        }
      } else if (event is DevToolsResponse) {
        if (!event.success) {
          final alert = 'DevTools failed to open with:\n${event.error}';
          if (event.promptExtension && window.confirm(alert)) {
            window.open('https://goo.gle/dart-debug-extension', '_blank');
          } else {
            window.alert(alert);
          }
        }
      } else if (event is RunRequest) {
        runMain();
      } else if (event is ErrorResponse) {
        window.console.error('Error from backend:\n\nError: ${event.error}\n\n'
            'Stack Trace:\n${event.stackTrace}');
      }
    },
    onError: (error) {
      // An error is propagated on a full page reload as Chrome presumably
      // forces the SSE connection to close in a bad state. This does not cause
      // any adverse effects so simply swallow this error as to not print the
      // misleading unhandled error message.
    },
  );

  // Launch devtools on key press
  if (appInfo.enableDevToolsLaunch) {
    window.onKeyDown.listen((Event e) {
      if (e is KeyboardEvent &&
          const [
            'd',
            'D',
            '∂', // alt-d output on Mac
            'Î', // shift-alt-D output on Mac
          ].contains(e.key) &&
          e.altKey &&
          !e.ctrlKey &&
          !e.metaKey) {
        e.preventDefault();
        launchDevToolsJs();
      }
    });
  }

  // Connect to the server
  if (_isChromium) {
    print(
        'Injected Client $dartAppInstanceId: sending connect request with ${appInfo.appName} (${appInfo.entrypoints})');
    connection.sendConnectRequest(
      appInfo.appName,
      appInfo.appId,
      appInfo.appInstanceId,
      appInfo.entrypoints,
    );
  } else {
    // If not Chromium we just invoke main, devtools aren't supported.
    runMain();
  }
  _launchCommunicationWithDebugExtension(appInfo);
}

void _launchCommunicationWithDebugExtension(AppInfo appInfo) {
  // Listen for an event from the Dart Debug Extension to authenticate the
  // user (sent once the extension receives the dart-app-read event):
  _listenForDebugExtensionAuthRequest(appInfo);

  // Send the dart-app-ready event along with debug info to the Dart Debug
  // Extension so that it can debug the Dart app:
  final debugInfoJson = jsonEncode(
    serializers.serialize(
      DebugInfo(
        (b) => b
          ..appEntrypointPath = appInfo.appName
          ..appId = appInfo.appId
          ..appInstanceId = appInfo.appInstanceId
          ..appOrigin = window.location.origin
          ..appUrl = window.location.href
          ..authUrl = authUrl(appInfo.extensionUrl)
          ..extensionUrl = appInfo.extensionUrl
          ..isInternalBuild = appInfo.isInternalBuild
          ..isFlutterApp = appInfo.isFlutterApp
          ..workspaceName = appInfo.workspaceName,
      ),
    ),
  );
  dispatchEvent(CustomEvent('dart-app-ready', detail: debugInfoJson));
}

String? authUrl(String? extensionUrl) {
  if (extensionUrl == null) return null;
  final authUrl = Uri.parse(extensionUrl).replace(path: authenticationPath);
  switch (authUrl.scheme) {
    case 'ws':
      return authUrl.replace(scheme: 'http').toString();
    case 'wss':
      return authUrl.replace(scheme: 'https').toString();
    default:
      return authUrl.toString();
  }
}

void _listenForDebugExtensionAuthRequest(AppInfo appInfo) {
  window.addEventListener(
    'message',
    allowInterop((event) async {
      final messageEvent = event as MessageEvent;
      if (messageEvent.data is! String) return;
      if (messageEvent.data as String != 'dart-auth-request') return;

      // Notify the Dart Debug Extension of authentication status:
      final auth = authUrl(appInfo.extensionUrl);
      if (auth != null) {
        final isAuthenticated = await _authenticateUser(auth);
        dispatchEvent(
          CustomEvent('dart-auth-response', detail: '$isAuthenticated'),
        );
      }
    }),
  );
}

Future<bool> _authenticateUser(String authUrl) async {
  final response = await HttpRequest.request(
    authUrl,
    method: 'GET',
    withCredentials: true,
  );
  final responseText = response.responseText ?? '';
  return responseText.contains('Dart Debug Authentication Success!');
}

class DevHandlerConnection {
  late final SocketClient client;

  final debugEventController =
      BatchedStreamController<DebugEvent>(delay: _batchDelayMilliseconds);

  DevHandlerConnection(String devHandlerPath) {
    final fixedPath = _fixProtocol(devHandlerPath);
    final fixedUri = Uri.parse(fixedPath);
    client = fixedUri.isScheme('ws') || fixedUri.isScheme('wss')
        ? WebSocketClient(WebSocketChannel.connect(fixedUri))
        : SseSocketClient(SseClient(fixedPath, debugKey: 'InjectedClient'));

    debugEventController.stream.listen(_sendBatchedDebugEvents);
  }

  void sendConnectRequest(
    String appName,
    String appId,
    String? appInstanceId,
    List<String> entrypoints,
  ) {
    _serializeAndTrySendEvent(ConnectRequest(
      (b) => b
        ..appName = appName
        ..appId = appId
        ..instanceId = appInstanceId
        ..entrypoints = ListBuilder<String>(entrypoints),
    ));
  }

  void sendRegisterEntrypointRequest(
    String appName,
    String entrypointPath,
  ) {
    _serializeAndTrySendEvent(RegisterEntrypointRequest(
      (b) => b
        ..appName = appName
        ..entrypointPath = entrypointPath,
    ));
  }

  void _sendBatchedDebugEvents(
    List<DebugEvent> events,
  ) {
    _serializeAndTrySendEvent(BatchedDebugEvents(
      (b) => b.events = ListBuilder<DebugEvent>(events),
    ));
  }

  void sendDebugEvent(String kind, String eventData) {
    _trySendEvent(
        debugEventController.sink,
        DebugEvent(
          (b) => b
            ..timestamp = (DateTime.now().millisecondsSinceEpoch)
            ..kind = kind
            ..eventData = eventData,
        ));
  }

  void sendRegisterEvent(String eventData) {
    _serializeAndTrySendEvent(RegisterEvent(
      (b) => b
        ..timestamp = (DateTime.now().millisecondsSinceEpoch)
        ..eventData = eventData,
    ));
  }

  void sendDevToolsRequest(String appId, String appInstanceId) {
    _serializeAndTrySendEvent(DevToolsRequest(
      (b) => b
        ..appId = appId
        ..instanceId = appInstanceId,
    ));
  }

  void _trySendEvent<T>(StreamSink<T> sink, T event) {
    try {
      sink.add(event);
    } on StateError catch (_) {
      // An error is propagated on a full page reload as Chrome presumably
      // forces the SSE connection to close in a bad state.
      print('Cannot send event $event. '
          'Injected client connection is closed.');
    }
  }

  void _serializeAndTrySendEvent<T>(T object) {
    _trySendEvent(client.sink, jsonEncode(serializers.serialize(object)));
  }

  /// Returns [url] modified if necessary so that, if the current page is served
  /// over `https`, then the URL is converted to `https`.
  String _fixProtocol(String url) {
    var uri = Uri.parse(url);
    if (window.location.protocol == 'https:' &&
        uri.scheme == 'http' &&
        // Chrome allows mixed content on localhost. It is not safe to assume the
        // server is also listening on https.
        uri.host != 'localhost') {
      uri = uri.replace(scheme: 'https');
    } else if (window.location.protocol == 'wss:' &&
        uri.scheme == 'ws' &&
        uri.host != 'localhost') {
      uri = uri.replace(scheme: 'wss');
    }
    return uri.toString();
  }
}

@JS(r'$dartAppId')
external String? get dartAppId; // used in extension and tests

@JS(r'$dartAppId')
external set dartAppId(String? id); // used in extension and tests

@JS(r'$dartAppInstanceId')
external String? get dartAppInstanceId; // used in extension and tests

@JS(r'$dartAppInstanceId')
external set dartAppInstanceId(String? id); // used in extension and tests

@JS(r'$loadModuleConfig') // used by require restarter
external set loadModuleConfig(Object Function(String module) load);

@JS(r'$dartHotRestartDwds')
external set hotRestartJs(Promise<bool> Function(String runId) cb);

@JS(r'$launchDevTools')
external void Function() get launchDevToolsJs;

@JS(r'$launchDevTools')
external set launchDevToolsJs(void Function() cb);

@JS('window.top.document.dispatchEvent')
external void dispatchEvent(CustomEvent event);

@JS(r'$emitDebugEvent')
external set emitDebugEvent(void Function(String, String) func);

@JS(r'$emitRegisterEvent')
external set emitRegisterEvent(void Function(String) func);

@JS(r'$dartAppInfo')
external AppInfo get dartAppInfo;

@JS(r'$dartRegisterEntrypoint')
external set registerEntrypoint(
  void Function(
    String appName,
    String entrypointPath,
  ) func,
);

bool get _isChromium => window.navigator.vendor.contains('Google');

@JS()
@anonymous
class AppInfo {
  external String get moduleStrategy;
  external String get reloadConfiguration;
  external Object Function(String module) get loadModuleConfig;
  external String get dwdsVersion;
  external bool get enableDevToolsLaunch;
  external bool get emitDebugEvents;
  external bool get isInternalBuild;
  external String get appName;
  external String get appId;
  external set appInstanceId(String id);
  external String get appInstanceId;
  external bool get isFlutterApp;
  external String? get extensionUrl;
  external String get devHandlerPath;
  external List<String> get entrypoints;
  external String? get workspaceName;
}
