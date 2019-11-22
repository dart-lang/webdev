// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library hot_reload_client;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/data/connect_request.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/error_response.dart';
import 'package:dwds/data/run_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:js/js.dart';
import 'package:sse/client/sse_client.dart';
import 'package:uuid/uuid.dart';

import 'promise.dart';
import 'reloader/legacy_restarter.dart';
import 'reloader/manager.dart';
import 'reloader/require_restarter.dart';
import 'reloader/restarter.dart';

export 'package:dwds/src/version.dart';

// GENERATE:
// pub run build_runner build web
Future<void> main() {
  return runZoned(() async {
    // Set the unique id for this instance of the app.
    // Test apps may already have this set.
    dartAppInstanceId ??= Uuid().v1();

    var client = SseClient(_fixProtocol('$dartUriBase/\$sseHandler'));
    // Ensure the SSE connection is established before proceeding.
    // Note that `onOpen` is a broadcast stream so we must listen for this
    // immediately.
    await client.onOpen.first;

    Restarter restarter;
    if (dartModuleStrategy == 'require') {
      restarter = await RequireRestarter.create();
    } else if (dartModuleStrategy == 'dart_library.import') {
      restarter = LegacyRestarter();
    } else {
      throw StateError('Unknown module strategy: $dartModuleStrategy');
    }

    var manager = ReloadingManager(client, restarter);

    hotRestartJs = allowInterop(() {
      return toPromise(manager.hotRestart());
    });

    launchDevToolsJs = allowInterop(() {
      if (!_isChrome) {
        window.alert('Dart DevTools is only supported on Chrome');
        return;
      }
      client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
        ..appId = dartAppId
        ..instanceId = dartAppInstanceId))));
    });

    client.stream.listen((serialized) async {
      var event = serializers.deserialize(jsonDecode(serialized));
      if (event is DefaultBuildResult) {
        if (reloadConfiguration == 'ReloadConfiguration.liveReload') {
          manager.reloadPage();
        } else if (reloadConfiguration == 'ReloadConfiguration.hotRestart') {
          await manager.hotRestart();
        } else if (reloadConfiguration == 'ReloadConfiguration.hotReload') {
          print('Hot reload is currently unsupported. Ignoring change.');
        }
      } else if (event is DevToolsResponse) {
        if (!event.success) {
          window.alert('DevTools failed to open with: ${event.error}');
        }
      } else if (event is RunRequest) {
        runMain();
      } else if (event is ErrorResponse) {
        window.console.error('Error from backend:\n\nError: ${event.error}\n\n'
            'Stack Trace:\n${event.stackTrace}');
      }
    }, onError: (error) {
      // An error is propagated on a full page reload as Chrome presumably
      // forces the SSE connection to close in a bad state. This does not cause
      // any adverse effects so simply swallow this error as to not print the
      // misleading unhandled error message.
    });

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

    if (_isChrome) {
      client.sink.add(jsonEncode(serializers.serialize(ConnectRequest((b) => b
        ..appId = dartAppId
        ..instanceId = dartAppInstanceId))));
    } else {
      // If not chrome we just invoke main, devtools aren't supported.
      runMain();
    }
  }, onError: (error, stackTrace) {
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

/// Returns [url] modified if necessary so that, if the current page is served
/// over `https`, then the URL is converted to `https`. Localhost is treated
/// as a special case and not modified.
String _fixProtocol(String url) {
  if (window.location.protocol == 'https:' && !url.startsWith('https://')) {
    // Chrome seems to allow mixed content from localhost.
    if (url.startsWith('http://localhost')) {
      return url;
    } else {
      return url.replaceFirst('http://', 'https://');
    }
  } else {
    return url;
  }
}

@JS(r'$dartAppId')
external String get dartAppId;

@JS(r'$dartAppInstanceId')
external String get dartAppInstanceId;

@JS(r'$dartUriBase')
external String get dartUriBase;

@JS(r'$dartAppInstanceId')
external set dartAppInstanceId(String id);

@JS(r'$dartModuleStrategy')
external String get dartModuleStrategy;

@JS(r'$dartHotRestart')
external set hotRestartJs(Promise<bool> Function() cb);

@JS(r'$launchDevTools')
external void Function() get launchDevToolsJs;

@JS(r'$launchDevTools')
external set launchDevToolsJs(void Function() cb);

@JS(r'$dartReloadConfiguration')
external String get reloadConfiguration;

/// Runs `window.$dartRunMain()` by injecting a script tag.
///
/// We do this so that we don't see user exceptions bubble up in our own error
/// handling zone.
void runMain() {
  var scriptElement = ScriptElement()..innerHtml = r'window.$dartRunMain();';
  document.body.append(scriptElement);
  Future.microtask(scriptElement.remove);
}

bool get _isChrome =>
    window.navigator.userAgent.contains('Chrome') &&
    // Edge has `Chrome` in its user agent string, but it also has `Edg` which
    // chrome doesn't.
    !window.navigator.userAgent.contains('Edg');
