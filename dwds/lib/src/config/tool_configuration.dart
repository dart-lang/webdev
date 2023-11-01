// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/servers/devtools.dart';
import 'package:dwds/src/services/expression_compiler.dart';

/// Configuration about the app, debug settings, and file system.
///
/// This is set by the code runner and passed to DWDS on start up.
class ToolConfiguration {
  final LoadStrategy loadStrategy;
  final DebugSettings debugSettings;
  final AppMetadata appMetadata;

  const ToolConfiguration({
    required this.loadStrategy,
    required this.debugSettings,
    required this.appMetadata,
  });
}

/// The tool configuration for the connected app.
///
/// TODO(elliette): Consider making this final (would require updating tests
/// that currently depend on changing the configuration between test cases).
late ToolConfiguration _globalToolConfiguration;
set globalToolConfiguration(ToolConfiguration configuration) =>
    _globalToolConfiguration = configuration;
ToolConfiguration get globalToolConfiguration => _globalToolConfiguration;

/// Metadata for the connected app.
///
/// These are set by the code runner and passed to DWDS on start up.
class AppMetadata {
  final String hostname;
  final bool isInternalBuild;
  final String? workspaceName;

  const AppMetadata({
    this.hostname = 'localhost',
    this.isInternalBuild = false,
    this.workspaceName,
  });
}

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

  const DebugSettings({
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
