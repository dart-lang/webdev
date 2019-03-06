// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

import '../serve/injected/configuration.dart';

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
  var reload = ReloadConfiguration.none;
  var hotReload = argResults.options.contains(hotReloadFlag)
      ? argResults[hotReloadFlag] as bool
      : false;
  var hotRestart = argResults.options.contains(hotRestartFlag)
      ? argResults[hotRestartFlag] as bool
      : false;
  var liveReload = argResults.options.contains(liveReloadFlag)
      ? argResults[liveReloadFlag] as bool
      : false;
  if ([hotReload, hotRestart, liveReload].where((v) => v).length > 1) {
    throw InvalidConfiguration('Can not use --$hotReloadFlag, --$hotRestartFlag'
        ' or --$liveReloadFlag together.');
  }
  if (hotReload) reload = ReloadConfiguration.hotReload;
  if (hotRestart) reload = ReloadConfiguration.hotRestart;
  if (liveReload) reload = ReloadConfiguration.liveReload;
  return reload;
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

  String get hostname => _hostname ?? 'localhost';

  bool get launchInChrome => _launchInChrome ?? false;

  bool get logRequests => _logRequests ?? false;

  String get output => _output ?? outputNone;

  bool get release => _release ?? false;

  ReloadConfiguration get reload => _reload ?? ReloadConfiguration.none;

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? true;

  bool get verbose => _verbose ?? false;

  /// Returns a new configuration with values updated from the parsed args.
  static Configuration fromArgs(ArgResults argResults) {
    var defaultConfiguration = Configuration._();
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
}
