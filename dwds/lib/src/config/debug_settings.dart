// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/servers/devtools.dart';
import 'package:dwds/src/services/expression_compiler.dart';

typedef UrlEncoder = Future<String> Function(String url);

typedef DevToolsLauncher = Future<DevTools> Function(String hostname);

/// Debug settings for the connected app.
///
/// These are set by the code runner and passed to DWDS on start up.
class DebugSettings {
  final bool enableDebugging;
  final bool enableDebugExtension;
  final bool useSseForDebugProxy;
  final bool useSseForDebugBackend;
  final bool useSseForInjectedClient;
  final bool spawnDds;
  final bool enableDevToolsLaunch;
  final bool launchDevToolsInNewWindow;
  final bool emitDebugEvents;
  final DevToolsLauncher? devToolsLauncher;
  final ExpressionCompiler? expressionCompiler;
  final UrlEncoder? urlEncoder;

  DebugSettings({
    this.enableDebugging = true,
    this.enableDebugExtension = false,
    this.useSseForDebugProxy = true,
    this.useSseForDebugBackend = true,
    this.useSseForInjectedClient = true,
    this.spawnDds = true,
    this.enableDevToolsLaunch = true,
    this.launchDevToolsInNewWindow = true,
    this.emitDebugEvents = true,
    this.devToolsLauncher,
    this.expressionCompiler,
    this.urlEncoder,
  });
}
