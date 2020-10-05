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
const launchAppOption = 'launch-app';
const launchInChromeFlag = 'launch-in-chrome';
const liveReloadFlag = 'live-reload';
const logRequestsFlag = 'log-requests';
const outputFlag = 'output';
const outputNone = 'NONE';
const releaseFlag = 'release';
const requireBuildWebCompilersFlag = 'build-web-compilers';
const verboseFlag = 'verbose';
const disableDdsFlag = 'disable-dds';

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
  final List<String> _launchApps;
  final bool _launchInChrome;
  final bool _logRequests;
  final String _output;
  final String outputInput;
  final String outputPath;
  final bool _release;
  final ReloadConfiguration _reload;
  final bool _requireBuildWebCompilers;
  final bool _verbose;
  final bool _disableDds;

  Configuration({
    bool autoRun,
    int chromeDebugPort,
    bool debugExtension,
    bool debug,
    bool enableInjectedClient,
    String hostname,
    String tlsCertChain,
    String tlsCertKey,
    List<String> launchApps,
    bool launchInChrome,
    bool logRequests,
    String output,
    this.outputInput,
    this.outputPath,
    ReloadConfiguration reload,
    bool release,
    bool requireBuildWebCompilers,
    bool verbose,
    bool disableDds,
  })  : _autoRun = autoRun,
        _chromeDebugPort = chromeDebugPort,
        _debugExtension = debugExtension,
        _debug = debug,
        _enableInjectedClient = enableInjectedClient,
        _hostname = hostname,
        _tlsCertChain = tlsCertChain,
        _tlsCertKey = tlsCertKey,
        _launchApps = launchApps,
        _launchInChrome = launchInChrome,
        _logRequests = logRequests,
        _output = output,
        _release = release,
        _reload = reload,
        _requireBuildWebCompilers = requireBuildWebCompilers,
        _verbose = verbose,
        _disableDds = disableDds {
    _validateConfiguration();
  }

  void _validateConfiguration() {
    // Both null and an empty string are valid values for outputInput. For any
    // other value, we need to ensure it's a top-level dir.
    if (outputInput?.isNotEmpty ?? false) ensureIsTopLevelDir(outputInput);

    if ((tlsCertKey != null && tlsCertChain == null) ||
        (tlsCertKey == null && tlsCertChain != null)) {
      throw InvalidConfiguration(
          'Must use --$tlsCertKey with --$tlsCertChain.');
    }
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
      if (chromeDebugPort != 0) {
        throw InvalidConfiguration('--$chromeDebugPortFlag cannot be used '
            'with --no-$enableInjectedClientFlag');
      }
    }

    if (launchApps.isNotEmpty && !launchInChrome) {
      throw InvalidConfiguration(
          '--$launchAppOption can only be used with --$launchInChromeFlag');
    }
  }

  /// Creates a new [Configuration] with all non-null fields from
  /// [other] overriding the values of `this`.
  Configuration _override(Configuration other) => Configuration(
      autoRun: other._autoRun ?? _autoRun,
      chromeDebugPort: other._chromeDebugPort ?? _chromeDebugPort,
      debugExtension: other._debugExtension ?? _debugExtension,
      debug: other._debug ?? _debug,
      enableInjectedClient:
          other._enableInjectedClient ?? _enableInjectedClient,
      hostname: other._hostname ?? _hostname,
      tlsCertChain: other._tlsCertChain ?? _tlsCertChain,
      tlsCertKey: other._tlsCertKey ?? _tlsCertKey,
      launchApps: other._launchApps ?? _launchApps,
      launchInChrome: other._launchInChrome ?? _launchInChrome,
      logRequests: other._logRequests ?? _logRequests,
      output: other._output ?? _output,
      release: other._release ?? _release,
      reload: other._reload ?? _reload,
      requireBuildWebCompilers:
          other._requireBuildWebCompilers ?? _requireBuildWebCompilers,
      verbose: other._verbose ?? _verbose,
      disableDds: other._disableDds ?? _disableDds);

  factory Configuration.noInjectedClientDefaults() =>
      Configuration(autoRun: false, debug: false, debugExtension: false);

  // Whether the application should automatically run when loaded.
  bool get autoRun => _autoRun ?? true;

  int get chromeDebugPort => _chromeDebugPort ?? 0;

  bool get debugExtension => _debugExtension ?? false;

  bool get debug => _debug ?? false;

  bool get disableDds => _disableDds ?? false;

  bool get enableInjectedClient => _enableInjectedClient ?? true;

  String get hostname => _hostname ?? 'localhost';

  String get tlsCertChain => _tlsCertChain;

  String get tlsCertKey => _tlsCertKey;

  List<String> get launchApps => _launchApps ?? [];

  bool get launchInChrome => _launchInChrome ?? false;

  bool get logRequests => _logRequests ?? false;

  String get output => _output ?? outputNone;

  bool get release => _release ?? false;

  ReloadConfiguration get reload => _reload ?? ReloadConfiguration.none;

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? true;

  bool get verbose => _verbose ?? false;

  /// Returns a new configuration with values updated from the parsed args.
  static Configuration fromArgs(ArgResults argResults,
      {Configuration defaultConfiguration}) {
    defaultConfiguration ??= Configuration();
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
      defaultConfiguration = defaultConfiguration
          ._override(Configuration.noInjectedClientDefaults());
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

    var launchApps = argResults.options.contains(launchAppOption) &&
            argResults.wasParsed(launchAppOption)
        ? argResults[launchAppOption] as List<String>
        : defaultConfiguration.launchApps;

    var launchInChrome = argResults.options.contains(launchInChromeFlag) &&
            argResults.wasParsed(launchInChromeFlag)
        ? argResults[launchInChromeFlag] as bool
        // We want to default to launch chrome if the user provides just --debug
        // and not --chrome-debug-port.
        : debug &&
                !(argResults.options.contains(launchInChromeFlag) &&
                    argResults.wasParsed(chromeDebugPortFlag))
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
    if (output == 'NONE') {
      // The empty string means build everything.
      outputInput = '';
    } else {
      var splitOutput = output.split(':');
      if (splitOutput.length == 1) {
        // The empty string means build everything.
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

    var disableDds = argResults.options.contains(disableDdsFlag)
        ? argResults[disableDdsFlag] as bool
        : defaultConfiguration.disableDds;

    return Configuration(
        autoRun: defaultConfiguration.autoRun,
        chromeDebugPort: chromeDebugPort,
        debugExtension: debugExtension,
        debug: debug,
        enableInjectedClient: enableInjectedClient,
        hostname: hostname,
        tlsCertChain: tlsCertChain,
        tlsCertKey: tlsCertKey,
        launchApps: launchApps,
        launchInChrome: launchInChrome,
        logRequests: logRequests,
        output: output,
        outputInput: outputInput,
        outputPath: outputPath,
        release: release,
        reload: _parseReloadConfiguration(argResults),
        requireBuildWebCompilers: requireBuildWebCompilers,
        disableDds: disableDds,
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
