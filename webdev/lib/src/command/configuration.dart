// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';
import 'package:logging/logging.dart';

import '../serve/injected/configuration.dart';
import '../serve/logging.dart';
import '../util.dart';

const autoOption = 'auto';
const chromeDebugPortFlag = 'chrome-debug-port';
const debugFlag = 'debug';
const hostnameFlag = 'hostname';
const hotReloadFlag = 'hot-reload';
const hotRestartFlag = 'hot-restart';
const launchInChromeFlag = 'launch-in-chrome';
const liveReloadFlag = 'live-reload';
const logRequestsFlag = 'log-requests';
const outputFlag = 'output';
const outputNone = 'NONE';
const releaseFlag = 'release';
const requireBuildWebCompilersFlag = 'build-web-compilers';
const verboseFlag = 'verbose';

ReloadConfiguration _parseReloadConfiguration(ArgResults argResults) {
  var auto = argResults.options.contains(autoOption)
      ? argResults[autoOption] as String
      : null;

  void _handleDeprecatedFlag(String flag, String autoFallback) {
    if (argResults.options.contains(flag) &&
        argResults.wasParsed(flag) &&
        argResults[flag] as bool == true) {
      logHandler(
          Level.WARNING,
          '--$flag is deprecated please use --auto=$autoFallback instead '
          '(this has been automatically selected).');
      if (auto != null) {
        logHandler(
            Level.WARNING,
            'Only one --auto option is allowed, got $flag which corresponds '
            'to --auto=$autoFallback, but already got --auto=$auto');
      } else {
        auto = autoFallback;
      }
    }
  }

  _handleDeprecatedFlag(hotReloadFlag, 'reload');
  _handleDeprecatedFlag(hotRestartFlag, 'restart');
  _handleDeprecatedFlag(liveReloadFlag, 'refresh');

  switch (auto) {
    case 'reload':
      logHandler(
          Level.WARNING,
          'Hot reload is not yet supported for web projects. '
          'Please try --auto=restart instead.');
      return ReloadConfiguration.none;
    case 'restart':
      return ReloadConfiguration.hotRestart;
    case 'refresh':
      return ReloadConfiguration.liveReload;
    default:
      return ReloadConfiguration.none;
  }
}

class Configuration {
  final int _chromeDebugPort;
  final bool _debug;
  final String _hostname;
  final bool _launchInChrome;
  final bool _logRequests;
  final String _output;
  final bool _release;
  final ReloadConfiguration _reload;
  final bool _requireBuildWebCompilers;
  final bool _verbose;

  Configuration._({
    int chromeDebugPort,
    bool debug,
    String hostname,
    bool launchInChrome,
    bool logRequests,
    String output,
    ReloadConfiguration reload,
    bool release,
    bool requireBuildWebCompilers,
    bool verbose,
  })  : _chromeDebugPort = chromeDebugPort,
        _debug = debug,
        _hostname = hostname,
        _launchInChrome = launchInChrome,
        _logRequests = logRequests,
        _output = output,
        _release = release,
        _reload = reload,
        _requireBuildWebCompilers = requireBuildWebCompilers,
        _verbose = verbose;

  int get chromeDebugPort => _chromeDebugPort ?? 0;

  bool get debug => _debug ?? false;

  String get hostname => _hostname;

  bool get launchInChrome => _launchInChrome ?? false;

  bool get logRequests => _logRequests ?? false;

  String get output => _output ?? outputNone;

  bool get release => _release ?? false;

  ReloadConfiguration get reload => _reload ?? ReloadConfiguration.none;

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? true;

  bool get verbose => _verbose ?? false;

  static Future<Configuration> fromValues({
    int chromeDebugPort,
    bool debug,
    String hostname,
    bool launchInChrome,
    bool logRequests,
    String output,
    ReloadConfiguration reload,
    bool release,
    bool requireBuildWebCompilers,
    bool verbose,
  }) async {
    hostname ??= await supportsIpv6 ? '0.0.0.0' : 'localhost';
    return Configuration._(
      chromeDebugPort: chromeDebugPort,
      debug: debug,
      hostname: hostname,
      launchInChrome: launchInChrome,
      logRequests: logRequests,
      output: output,
      reload: reload,
      release: release,
      requireBuildWebCompilers: requireBuildWebCompilers,
      verbose: verbose,
    );
  }

  /// Returns a new configuration with values updated from the parsed args.
  static Future<Configuration> fromArgs(ArgResults argResults) async {
    var defaultConfiguration = await fromValues();
    if (argResults == null) return defaultConfiguration;

    var chromeDebugPort = argResults.options.contains(chromeDebugPortFlag)
        ? int.parse(argResults[chromeDebugPortFlag] as String)
        : defaultConfiguration.chromeDebugPort;

    var debug = argResults.options.contains(debugFlag)
        ? argResults[debugFlag] as bool
        : defaultConfiguration.debug;

    var hostname = argResults.options.contains(hostnameFlag)
        ? argResults[hostnameFlag] as String
        : defaultConfiguration.hostname;

    var launchInChrome = argResults.options.contains(launchInChromeFlag)
        ? argResults[launchInChromeFlag] as bool
        : defaultConfiguration.launchInChrome;

    var logRequests = argResults.options.contains(logRequestsFlag)
        ? argResults[logRequestsFlag] as bool
        : defaultConfiguration.logRequests;

    var output = argResults.options.contains(outputFlag)
        ? argResults[outputFlag] as String
        : defaultConfiguration.output;

    var release = argResults.options.contains(releaseFlag)
        ? argResults[releaseFlag] as bool
        : defaultConfiguration.release;

    var requireBuildWebCompilers =
        argResults.options.contains(requireBuildWebCompilersFlag)
            ? argResults[requireBuildWebCompilersFlag] as bool
            : defaultConfiguration.requireBuildWebCompilers;

    var verbose = argResults.options.contains(verboseFlag)
        ? argResults[verboseFlag] as bool
        : defaultConfiguration.verbose;

    if (debug && chromeDebugPort == 0 && !launchInChrome) {
      throw InvalidConfiguration(
          'Must either use --$chromeDebugPortFlag or --$launchInChrome with '
          '--$debugFlag.');
    }

    return Configuration._(
        chromeDebugPort: chromeDebugPort,
        debug: debug,
        hostname: hostname,
        launchInChrome: launchInChrome,
        logRequests: logRequests,
        output: output,
        release: release,
        reload: _parseReloadConfiguration(argResults),
        requireBuildWebCompilers: requireBuildWebCompilers,
        verbose: verbose);
  }
}

class InvalidConfiguration implements Exception {
  final String details;
  InvalidConfiguration(this.details);

  @override
  String toString() {
    return 'Invalid configuration: $details';
  }
}
