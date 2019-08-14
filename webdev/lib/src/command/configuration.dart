// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';
import 'package:dwds/dwds.dart';
import 'package:logging/logging.dart';

import '../logging.dart';
import 'shared.dart';

const autoOption = 'auto';
const chromeDebugPortFlag = 'chrome-debug-port';
const debugExtensionFlag = 'debug-extension';
const debugFlag = 'debug';
const enableInjectedClientFlag = 'injected-client';
const hostnameFlag = 'hostname';
const tlsCertChainFlag = 'tls-cert-chain';
const tlsCertKeyFlag = 'tls-cert-key';
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
      logWriter(
          Level.WARNING,
          '--$flag is deprecated please use --auto=$autoFallback instead '
          '(this has been automatically selected).');
      if (auto != null) {
        logWriter(
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
      logWriter(
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
  final bool _autoRun;
  final int _chromeDebugPort;
  final bool _debugExtension;
  final bool _debug;
  final bool _enableInjectedClient;
  final String _hostname;
  final String _tlsCertChain;
  final String _tlsCertKey;
  final bool _launchInChrome;
  final bool _logRequests;
  final String _output;
  final String outputInput;
  final String outputPath;
  final bool _release;
  final ReloadConfiguration _reload;
  final bool _requireBuildWebCompilers;
  final bool _verbose;

  Configuration({
    bool autoRun,
    int chromeDebugPort,
    bool debugExtension,
    bool debug,
    bool enableInjectedClient,
    String hostname,
    String tlsCertChain,
    String tlsCertKey,
    bool launchInChrome,
    bool logRequests,
    String output,
    this.outputInput,
    this.outputPath,
    ReloadConfiguration reload,
    bool release,
    bool requireBuildWebCompilers,
    bool verbose,
  })  : _autoRun = autoRun,
        _chromeDebugPort = chromeDebugPort,
        _debugExtension = debugExtension,
        _debug = debug,
        _enableInjectedClient = enableInjectedClient,
        _hostname = hostname,
        _tlsCertChain = tlsCertChain,
        _tlsCertKey = tlsCertKey,
        _launchInChrome = launchInChrome,
        _logRequests = logRequests,
        _output = output,
        _release = release,
        _reload = reload,
        _requireBuildWebCompilers = requireBuildWebCompilers,
        _verbose = verbose {
    if (outputInput != null) ensureIsTopLevelDir(outputInput);
  }

  factory Configuration.noInjectedClientDefaults() =>
      Configuration(autoRun: false, debug: false, debugExtension: false);

  // Whether the application should automatically run when loaded.
  bool get autoRun => _autoRun ?? true;

  int get chromeDebugPort => _chromeDebugPort ?? 0;

  bool get debugExtension => _debugExtension ?? false;

  bool get debug => _debug ?? false;

  bool get enableInjectedClient => _enableInjectedClient ?? true;

  String get hostname => _hostname ?? 'localhost';

  String get tlsCertChain => _tlsCertChain;

  String get tlsCertKey => _tlsCertKey;

  bool get launchInChrome => _launchInChrome ?? false;

  bool get logRequests => _logRequests ?? false;

  String get output => _output ?? outputNone;

  bool get release => _release ?? false;

  ReloadConfiguration get reload => _reload ?? ReloadConfiguration.none;

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? true;

  bool get verbose => _verbose ?? false;

  /// Returns a new configuration with values updated from the parsed args.
  static Configuration fromArgs(ArgResults argResults) {
    var defaultConfiguration = Configuration();
    if (argResults == null) return defaultConfiguration;

    var enableInjectedClient =
        argResults.options.contains(enableInjectedClientFlag)
            ? argResults[enableInjectedClientFlag] as bool
            : defaultConfiguration.enableInjectedClient;

    // Change the defaults when we have no injected client to disable all
    // debugging features.
    //
    // After parsing we check these defaults weren't overridden as well.
    if (!enableInjectedClient) {
      defaultConfiguration = Configuration.noInjectedClientDefaults();
    }

    var chromeDebugPort = argResults.options.contains(chromeDebugPortFlag)
        ? int.parse(argResults[chromeDebugPortFlag] as String)
        : defaultConfiguration.chromeDebugPort;

    var debugExtension = argResults.options.contains(debugExtensionFlag)
        ? argResults[debugExtensionFlag] as bool
        : defaultConfiguration.debugExtension;

    var debug = argResults.options.contains(debugFlag)
        ? argResults[debugFlag] as bool
        : defaultConfiguration.debug;

    var hostname = argResults.options.contains(hostnameFlag)
        ? argResults[hostnameFlag] as String
        : defaultConfiguration.hostname;

    var tlsCertChain = argResults.options.contains(tlsCertChainFlag)
        ? argResults[tlsCertChainFlag] as String
        : defaultConfiguration.tlsCertChain;

    var tlsCertKey = argResults.options.contains(tlsCertKeyFlag)
        ? argResults[tlsCertKeyFlag] as String
        : defaultConfiguration.tlsCertKey;

    var launchInChrome = argResults.options.contains(launchInChromeFlag) &&
            argResults.wasParsed(launchInChromeFlag)
        ? argResults[launchInChromeFlag] as bool
        // We want to default to launch chrome if the user provides just --debug
        // and not --chrome-debug-port.
        : debug && !argResults.wasParsed(chromeDebugPortFlag)
            ? true
            : defaultConfiguration.launchInChrome;

    var logRequests = argResults.options.contains(logRequestsFlag)
        ? argResults[logRequestsFlag] as bool
        : defaultConfiguration.logRequests;

    var output = argResults.options.contains(outputFlag)
        ? argResults[outputFlag] as String
        : defaultConfiguration.output;

    String outputPath;
    String outputInput;
    if (output != 'NONE') {
      var splitOutput = output.split(':');
      if (splitOutput.length == 1) {
        outputInput = '';
        outputPath = output;
      } else {
        outputInput = splitOutput.first;
        outputPath = splitOutput.skip(1).join(':');
      }
    }

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
          'Must either use --$chromeDebugPortFlag or --$launchInChromeFlag '
          'with --$debugFlag.');
    }

    // Check that no debugging options were passed if the injected client is
    // disabled.
    if (!enableInjectedClient) {
      if (debug) {
        throw InvalidConfiguration(
            '--$debugFlag cannot be used with --no-$enableInjectedClientFlag');
      }
      if (debugExtension) {
        throw InvalidConfiguration('--$debugExtensionFlag cannot be used with '
            '--no-$enableInjectedClientFlag');
      }
      if (chromeDebugPort != defaultConfiguration.chromeDebugPort) {
        throw InvalidConfiguration('--$chromeDebugPortFlag cannot be used '
            'with --no-$enableInjectedClientFlag');
      }
    }

    return Configuration(
        chromeDebugPort: chromeDebugPort,
        debugExtension: debugExtension,
        debug: debug,
        enableInjectedClient: enableInjectedClient,
        hostname: hostname,
        tlsCertChain: tlsCertChain,
        tlsCertKey: tlsCertKey,
        launchInChrome: launchInChrome,
        logRequests: logRequests,
        output: output,
        outputInput: outputInput,
        outputPath: outputPath,
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
