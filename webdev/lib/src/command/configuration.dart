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

  Configuration({
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

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? false;

  bool get verbose => _verbose ?? false;

  /// Returns a new configuration with values updated from the parsed args.
  Configuration mergeArgs(ArgResults argResults) {
    if (argResults == null) return this;

    var hostname = argResults.options.contains(hostnameFlag) &&
            argResults.wasParsed(hostnameFlag)
        ? argResults[hostnameFlag] as String
        : this.hostname;

    var hotReload = argResults.options.contains(hotReloadFlag) &&
            argResults.wasParsed(hotReloadFlag)
        ? argResults[hotReloadFlag] as bool
        : this.hotReload;

    var hotRestart = argResults.options.contains(hotRestartFlag) &&
            argResults.wasParsed(hotRestartFlag)
        ? argResults[hotRestartFlag] as bool
        : this.hotRestart;

    var launchInChrome = argResults.options.contains(launchInChromeFlag) &&
            argResults.wasParsed(launchInChromeFlag)
        ? argResults[launchInChromeFlag] as bool
        : this.liveReload;

    var liveReload = argResults.options.contains(liveReloadFlag) &&
            argResults.wasParsed(liveReloadFlag)
        ? argResults[liveReloadFlag] as bool
        : this.liveReload;

    var logRequests = argResults.options.contains(logRequestsFlag) &&
            argResults.wasParsed(logRequestsFlag)
        ? argResults[logRequestsFlag] as bool
        : this.logRequests;

    var output = argResults.options.contains(outputFlag) &&
            argResults.wasParsed(outputFlag)
        ? argResults[outputFlag] as String
        : this.output;

    var release = argResults.options.contains(releaseFlag) &&
            argResults.wasParsed(releaseFlag)
        ? argResults[releaseFlag] as bool
        : this.release;

    var requireBuildWebCompilers =
        argResults.options.contains(requireBuildWebCompilersFlag) &&
                argResults.wasParsed(requireBuildWebCompilersFlag)
            ? argResults[requireBuildWebCompilersFlag] as bool
            : this.requireBuildWebCompilers;

    var verbose = argResults.options.contains(verboseFlag) &&
            argResults.wasParsed(verboseFlag)
        ? argResults[verboseFlag] as bool
        : this.verbose;

    return Configuration(
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
