// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

const hostnameFlag = 'hostname';
const hotReloadFlag = 'hot-reload';
const hotRestartFlag = 'hot-restart';
const liveReloadFlag = 'live-reload';
const logRequestsFlag = 'log-requests';
const outputFlag = 'output';
const outputNone = 'NONE';
const releaseFlag = 'release';
const requireBuildWebCompilersFlag = 'build-web-compilers';
const verboseFlag = 'verbose';

const _configurationFile = 'webdev.yaml';

class Configuration {
  final String _hostname;
  final bool _hotReload;
  final bool _hotRestart;
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
    bool liveReload,
    bool logRequests,
    String output,
    bool release,
    bool requireBuildWebCompilers,
    bool verbose,
  })  : _hostname = hostname,
        _hotReload = hotReload,
        _hotRestart = hotRestart,
        _liveReload = liveReload,
        _logRequests = logRequests,
        _output = output,
        _release = release,
        _requireBuildWebCompilers = requireBuildWebCompilers,
        _verbose = verbose;

  String get hostname => _hostname ?? 'localhost';

  bool get hotReload => _hotReload ?? false;

  bool get hotRestart => _hotRestart ?? false;

  bool get liveReload => _liveReload ?? false;

  bool get logRequests => _logRequests ?? false;

  String get output => _output ?? outputNone;

  bool get release => _release ?? false;

  bool get requireBuildWebCompilers => _requireBuildWebCompilers ?? false;

  bool get verbose => _verbose ?? false;

  /// Returns a new configuration with values updated from the parsed args.
  Configuration _mergeArgs(ArgResults argResults) {
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
        liveReload: liveReload,
        logRequests: logRequests,
        output: output,
        release: release,
        requireBuildWebCompilers: requireBuildWebCompilers,
        verbose: verbose);
  }
}

class ConfigurationLoader {
  final String _source;
  final YamlMap _document;

  ConfigurationLoader._(this._source, this._document);

  /// Throws a [SourceSpanFormatException] with [message] about [field].
  void _error(String message, String field) {
    throw SourceSpanFormatException(
        message, _document.nodes[field].span, _source);
  }

  /// Asserts that [field] is a boolean and returns its value.
  bool _getBool(String field) =>
      _getValue(field, 'boolean', (value) => value is bool) as bool;

  /// Asserts that [field] is a string and returns its value.
  String _getString(String field) =>
      _getValue(field, 'string', (value) => value is String) as String;

  /// Returns the value of the node at [field].
  ///
  /// If [typeTest] returns `false` for that value, instead throws an error
  /// complaining that the field is not a [typeName].
  dynamic _getValue(String field, String typeName, bool typeTest(value)) {
    var value = _document[field];
    if (value == null || typeTest(value)) return value;
    _error('$field is not $typeName.', field);
  }

  Configuration _parseAndMergeConfiguration(
      Configuration defaultConfiguration) {
    var hostname = _getString(hostnameFlag);
    var hotReload = _getBool(hotReloadFlag);
    var hotRestart = _getBool(hotRestartFlag);
    var liveReload = _getBool(liveReloadFlag);
    var logRequests = _getBool(logRequestsFlag);
    var output = _getString(outputFlag);
    var release = _getBool(releaseFlag);
    var requireBuildWebCompilers = _getBool(requireBuildWebCompilersFlag);
    var verbose = _getBool(verboseFlag);

    return Configuration(
        hostname: hostname ?? defaultConfiguration.hostname,
        hotReload: hotReload ?? defaultConfiguration.hotReload,
        hotRestart: hotRestart ?? defaultConfiguration.hotRestart,
        liveReload: liveReload ?? defaultConfiguration.liveReload,
        logRequests: logRequests ?? defaultConfiguration.logRequests,
        output: output ?? defaultConfiguration.output,
        release: release ?? defaultConfiguration.release,
        requireBuildWebCompilers: requireBuildWebCompilers ??
            defaultConfiguration.requireBuildWebCompilers,
        verbose: verbose ?? defaultConfiguration.verbose);
  }

  /// Loads the configuration and merges the provided arguments.
  ///
  /// Configuration from [argResults] takes precedence to configuration in the
  /// [defaultConfiguration] which takes to precedence to configuration found in
  /// [Configuration].
  static Configuration load({
    Configuration defaultConfiguration,
    ArgResults argResults,
    String filePath,
  }) {
    defaultConfiguration ??= Configuration();
    filePath ??= _configurationFile;
    var yamlFile = File(filePath);
    if (!yamlFile.existsSync()) {
      return defaultConfiguration._mergeArgs(argResults);
    }

    var source = yamlFile.readAsStringSync();
    var document = loadYamlNode(source);

    if (document.value == null) {
      return defaultConfiguration._mergeArgs(argResults);
    }

    if (document is! Map) {
      throw SourceSpanFormatException(
          'The configuration must be a YAML map.', document.span, source);
    }
    return ConfigurationLoader._(source, document as YamlMap)
        ._parseAndMergeConfiguration(defaultConfiguration)
        ._mergeArgs(argResults);
  }
}
