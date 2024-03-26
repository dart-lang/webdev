// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library hot_reload_client;

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/data/connect_request.dart';
import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/error_response.dart';
import 'package:dwds/data/extension_request.dart';
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
import 'reloader/ddc_restarter.dart';
import 'reloader/manager.dart';
import 'reloader/require_restarter.dart';
import 'reloader/restarter.dart';
import 'run_main.dart';

const _batchDelayMilliseconds = 1000;

// GENERATE:
// pub run build_runner build web
Future<void>? main() {
  return runZonedGuarded(() async {
    // Set the unique id for this instance of the app.
    // Test apps may already have this set.
    dartAppInstanceId ??= const Uuid().v1();

    final fixedPath = _fixProtocol(dwdsDevHandlerPath);
    final fixedUri = Uri.parse(fixedPath);
    final client = fixedUri.isScheme('ws') || fixedUri.isScheme('wss')
        ? WebSocketClient(WebSocketChannel.connect(fixedUri))
        : SseSocketClient(SseClient(fixedPath, debugKey: 'InjectedClient'));

    Restarter restarter;
    if (dartModuleStrategy == 'require-js') {
      restarter = await RequireRestarter.create();
    } else if (dartModuleStrategy == 'ddc' || dartModuleStrategy == 'legacy') {
      restarter = DdcRestarter();
    } else {
      throw StateError('Unknown module strategy: $dartModuleStrategy');
    }

    final manager = ReloadingManager(client, restarter);

    Completer? readyToRunMainCompleter;

    hotRestartJs = allowInterop((String runId, [bool? pauseIsolatesOnStart]) {
      if (pauseIsolatesOnStart ?? false) {
        readyToRunMainCompleter = Completer();
        return toPromise(
          manager.hotRestart(
            runId: runId,
            readyToRunMain: readyToRunMainCompleter!.future,
          ),
        );
      } else {
        return toPromise(manager.hotRestart(runId: runId));
      }
    });

    readyToRunMainJs = allowInterop(() {
      if (readyToRunMainCompleter == null) return;
      if (readyToRunMainCompleter!.isCompleted) return;
      readyToRunMainCompleter!.complete();
      readyToRunMainCompleter = null;
    });

    final debugEventController =
        BatchedStreamController<DebugEvent>(delay: _batchDelayMilliseconds);
    debugEventController.stream.listen((events) {
      if (dartEmitDebugEvents) {
        _trySendEvent(
          client.sink,
          jsonEncode(
            serializers.serialize(
              BatchedDebugEvents(
                (b) => b.events = ListBuilder<DebugEvent>(events),
              ),
            ),
          ),
        );
      }
    });

    emitDebugEvent = allowInterop((String kind, String eventData) {
      if (dartEmitDebugEvents) {
        _trySendEvent(
          debugEventController.sink,
          DebugEvent(
            (b) => b
              ..timestamp = (DateTime.now().millisecondsSinceEpoch)
              ..kind = kind
              ..eventData = eventData,
          ),
        );
      }
    });

    emitRegisterEvent = allowInterop((String eventData) {
      _trySendEvent(
        client.sink,
        jsonEncode(
          serializers.serialize(
            RegisterEvent(
              (b) => b
                ..timestamp = (DateTime.now().millisecondsSinceEpoch)
                ..eventData = eventData,
            ),
          ),
        ),
      );
    });

    launchDevToolsJs = allowInterop(() {
      if (!_isChromium) {
        window.alert(
          'Dart DevTools is only supported on Chromium based browsers.',
        );
        return;
      }
      _trySendEvent(
        client.sink,
        jsonEncode(
          serializers.serialize(
            DevToolsRequest(
              (b) => b
                ..appId = dartAppId
                ..instanceId = dartAppInstanceId,
            ),
          ),
        ),
      );
    });

    client.stream.listen(
      (serialized) async {
        final event = serializers.deserialize(jsonDecode(serialized));
        if (event is BuildResult) {
          if (reloadConfiguration == 'ReloadConfiguration.liveReload') {
            manager.reloadPage();
          } else if (reloadConfiguration == 'ReloadConfiguration.hotRestart') {
            await manager.hotRestart();
          } else if (reloadConfiguration == 'ReloadConfiguration.hotReload') {
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
          window.console
              .error('Error from backend:\n\nError: ${event.error}\n\n'
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

    if (dwdsEnableDevToolsLaunch) {
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

    if (_isChromium) {
      _trySendEvent(
        client.sink,
        jsonEncode(
          serializers.serialize(
            ConnectRequest(
              (b) => b
                ..appId = dartAppId
                ..instanceId = dartAppInstanceId
                ..entrypointPath = dartEntrypointPath,
            ),
          ),
        ),
      );
    } else {
      // If not Chromium we just invoke main, devtools aren't supported.
      runMain();
    }
    _launchCommunicationWithDebugExtension();
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

void _trySendEvent<T>(StreamSink<T> sink, T serialized) {
  try {
    sink.add(serialized);
  } on StateError catch (_) {
    // An error is propagated on a full page reload as Chrome presumably
    // forces the SSE connection to close in a bad state.
    print('Cannot send event $serialized. '
        'Injected client connection is closed.');
  }
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

void _launchCommunicationWithDebugExtension() {
  // Listen for an event from the Dart Debug Extension to authenticate the
  // user (sent once the extension receives the dart-app-read event):
  _listenForDebugExtensionAuthRequest();

  // Send the dart-app-ready event along with debug info to the Dart Debug
  // Extension so that it can debug the Dart app:
  final debugInfoJson = jsonEncode(
    serializers.serialize(
      DebugInfo(
        (b) => b
          ..appEntrypointPath = dartEntrypointPath
          ..appId = _appId
          ..appInstanceId = dartAppInstanceId
          ..appOrigin = window.location.origin
          ..appUrl = window.location.href
          ..authUrl = _authUrl
          ..extensionUrl = _extensionUrl
          ..isInternalBuild = _isInternalBuild
          ..isFlutterApp = _isFlutterApp
          ..workspaceName = dartWorkspaceName,
      ),
    ),
  );
  dispatchEvent(CustomEvent('dart-app-ready', detail: debugInfoJson));
}

void _listenForDebugExtensionAuthRequest() {
  window.addEventListener(
    'message',
    allowInterop((event) async {
      final messageEvent = event as MessageEvent;
      if (messageEvent.data is! String) return;
      if (messageEvent.data as String != 'dart-auth-request') return;

      // Notify the Dart Debug Extension of authentication status:
      if (_authUrl != null) {
        final isAuthenticated = await _authenticateUser(_authUrl!);
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

@JS(r'$dartAppId')
external String get dartAppId;

@JS(r'$dartAppInstanceId')
external String? get dartAppInstanceId;

@JS(r'$dwdsDevHandlerPath')
external String get dwdsDevHandlerPath;

@JS(r'$dartAppInstanceId')
external set dartAppInstanceId(String? id);

@JS(r'$dartModuleStrategy')
external String get dartModuleStrategy;

@JS(r'$dartHotRestartDwds')
external set hotRestartJs(
  Promise<bool> Function(String runId, [bool? pauseIsolatesOnStart]) cb,
);

@JS(r'$dartReadyToRunMain')
external set readyToRunMainJs(void Function() cb);

@JS(r'$launchDevTools')
external void Function() get launchDevToolsJs;

@JS(r'$launchDevTools')
external set launchDevToolsJs(void Function() cb);

@JS(r'$dartReloadConfiguration')
external String get reloadConfiguration;

@JS(r'$dartEntrypointPath')
external String get dartEntrypointPath;

@JS(r'$dwdsEnableDevToolsLaunch')
external bool get dwdsEnableDevToolsLaunch;

@JS('window.top.document.dispatchEvent')
external void dispatchEvent(CustomEvent event);

@JS(r'$dartEmitDebugEvents')
external bool get dartEmitDebugEvents;

@JS(r'$emitDebugEvent')
external set emitDebugEvent(void Function(String, String) func);

@JS(r'$emitRegisterEvent')
external set emitRegisterEvent(void Function(String) func);

@JS(r'$isInternalBuild')
external bool get isInternalBuild;

@JS(r'$isFlutterApp')
external bool get isFlutterApp;

@JS(r'$dartWorkspaceName')
external String? get dartWorkspaceName;

bool get _isChromium => window.navigator.vendor.contains('Google');

JsObject get _windowContext => JsObject.fromBrowserObject(window);

bool? get _isInternalBuild => _windowContext['\$isInternalBuild'];

bool? get _isFlutterApp => _windowContext['\$isFlutterApp'];

String? get _appId => _windowContext['\$dartAppId'];

String? get _extensionUrl => _windowContext['\$dartExtensionUri'];

String? get _authUrl {
  final extensionUrl = _extensionUrl;
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
