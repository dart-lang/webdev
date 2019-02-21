// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

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

class Configuration {
  final String _hostname;
  final bool _hotReload;
  final bool _hotRestart;
  final bool _launchInChrome;
  final bool _liveReload;
  final bool _logRequests;
  final String _output;
  final bool _release;
  final bool _requireBuildWebCompilers;
  final bool _verbose;

  Configuration._({
    String hostname,
    bool hotReload,
    bool hotRestart,
    bool launchInChrome,
    bool liveReload,
    bool logRequests,
    String output,
    bool release,
    bool requireBuildWebCompilers,
    bool verbose,
  })  : _hostname = hostname,
        _hotReload = hotReload,
        _hotRestart = hotRestart,
        _launchInChrome = launchInChrome,
        _liveReload = liveReload,
        _logRequests = logRequests,
        _output = output,
        _release = release,
        _requireBuildWebCompilers = requireBuildWebCompilers,
        _verbose = verbose;

  String get hostname => _hostname ?? 'localhost';

  bool get hotReload => _hotReload ?? false;

  bool get hotRestart => _hotRestart ?? false;

  bool get launchInChrome => _launchInChrome ?? false;

  bool get liveReload => _liveReload ?? false;

  bool get logRequests => _logRequests ?? false;

  String get output => _output ?? outputNone;

  bool get release => _release ?? false;

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? true;

  bool get verbose => _verbose ?? false;

  /// Returns a new configuration with values updated from the parsed args.
  static Configuration fromArgs(ArgResults argResults) {
    var defaultConfiguration = Configuration._();
    if (argResults == null) return defaultConfiguration;

    var hostname = argResults.options.contains(hostnameFlag)
        ? argResults[hostnameFlag] as String
        : defaultConfiguration.hostname;

    var hotReload = argResults.options.contains(hotReloadFlag)
        ? argResults[hotReloadFlag] as bool
        : defaultConfiguration.hotReload;

    var hotRestart = argResults.options.contains(hotRestartFlag)
        ? argResults[hotRestartFlag] as bool
        : defaultConfiguration.hotRestart;

    var launchInChrome = argResults.options.contains(launchInChromeFlag)
        ? argResults[launchInChromeFlag] as bool
        : defaultConfiguration.liveReload;

    var liveReload = argResults.options.contains(liveReloadFlag)
        ? argResults[liveReloadFlag] as bool
        : defaultConfiguration.liveReload;

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

    return Configuration._(
        hostname: hostname,
        hotReload: hotReload,
        hotRestart: hotRestart,
        launchInChrome: launchInChrome,
        liveReload: liveReload,
        logRequests: logRequests,
        output: output,
        release: release,
        requireBuildWebCompilers: requireBuildWebCompilers,
        verbose: verbose);
  }
}
