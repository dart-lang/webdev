// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library hot_reload_client;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:dwds/data/build_result.dart';
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
import 'run_main.dart';

// GENERATE:
// pub run build_runner build web
Future<void> main() {
  return runZonedGuarded(() async {
    // Set the unique id for this instance of the app.
    // Test apps may already have this set.
    dartAppInstanceId ??= const Uuid().v1();

    var client = SseClient(_fixProtocol(dwdsDevHandlerPath));

    Restarter restarter;
    if (dartModuleStrategy == 'require-js') {
      restarter = await RequireRestarter.create();
    } else if (dartModuleStrategy == 'legacy') {
      restarter = LegacyRestarter();
    } else {
      throw StateError('Unknown module strategy: $dartModuleStrategy');
    }

    var manager = ReloadingManager(client, restarter);

    hotRestartJs = allowInterop(() {
      return toPromise(manager.hotRestart());
    });

    launchDevToolsJs = allowInterop(() {
      if (!_isChromium) {
        window.alert(
            'Dart DevTools is only supported on Chromium based browsers.');
        return;
      }
      client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
        ..appId = dartAppId
        ..instanceId = dartAppInstanceId))));
    });

    client.stream.listen((serialized) async {
      var event = serializers.deserialize(jsonDecode(serialized));
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
          var alert = 'DevTools failed to open with:\n${event.error}';
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
    }, onError: (error) {
      // An error is propagated on a full page reload as Chrome presumably
      // forces the SSE connection to close in a bad state. This does not cause
      // any adverse effects so simply swallow this error as to not print the
      // misleading unhandled error message.
    });

    if (dwdsEnableDevtoolsLaunch) {
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
      client.sink.add(jsonEncode(serializers.serialize(ConnectRequest((b) => b
        ..appId = dartAppId
        ..instanceId = dartAppInstanceId
        ..entrypointPath = dartEntrypointPath))));
    } else {
      // If not Chromium we just invoke main, devtools aren't supported.
      runMain();
    }
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
  }
  return uri.toString();
}

@JS(r'$dartAppId')
external String get dartAppId;

@JS(r'$dartAppInstanceId')
external String get dartAppInstanceId;

@JS(r'$dwdsDevHandlerPath')
external String get dwdsDevHandlerPath;

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

@JS(r'$dartEntrypointPath')
external String get dartEntrypointPath;

@JS(r'$dwdsEnableDevtoolsLaunch')
external bool get dwdsEnableDevtoolsLaunch;

bool get _isChromium => window.navigator.userAgent.contains('Chrome');
