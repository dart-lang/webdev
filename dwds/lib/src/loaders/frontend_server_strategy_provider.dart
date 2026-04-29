// Copyright 2024 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/loaders/ddc.dart';
import 'package:dwds/src/loaders/ddc_library_bundle.dart';
import 'package:dwds/src/loaders/require.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:path/path.dart' as p;

const _defaultWebDirs = ['web', 'test', 'example', 'benchmark'];

abstract class FrontendServerStrategyProvider<T extends LoadStrategy> {
  final ReloadConfiguration _configuration;
  final AssetReader _assetReader;
  final PackageUriMapper _packageUriMapper;
  final Future<Map<String, String>> Function() _digestsProvider;
  final String _basePath;
  final BuildSettings _buildSettings;
  final String? _packageConfigPath;

  FrontendServerStrategyProvider(
    this._configuration,
    this._assetReader,
    this._packageUriMapper,
    this._digestsProvider,
    this._buildSettings, {
    this._packageConfigPath,
  }) : _basePath = _assetReader.basePath;

  T get strategy;

  String _removeBasePath(String path) {
    if (_basePath.isEmpty) return path;
    final stripped = stripLeadingSlashes(path);
    return stripLeadingSlashes(stripped.substring(_basePath.length));
  }

  String _addBasePath(String serverPath) => _basePath.isEmpty
      ? stripLeadingSlashes(serverPath)
      : '$_basePath/${stripLeadingSlashes(serverPath)}';

  String _removeJsExtension(String path) =>
      path.endsWith('.js') ? p.withoutExtension(path) : path;

  Future<Map<String, String>> _moduleProvider(
    MetadataProvider metadataProvider,
  ) async => (await metadataProvider.moduleToModulePath).map(
    (key, value) =>
        MapEntry(key, stripLeadingSlashes(_removeJsExtension(value))),
  );

  Future<String?> _moduleForServerPath(
    MetadataProvider metadataProvider,
    String serverPath,
  ) async {
    final modulePathToModule = await metadataProvider.modulePathToModule;
    final relativeServerPath = _removeBasePath(serverPath);
    return modulePathToModule[relativeServerPath];
  }

  Future<String> _serverPathForModule(
    MetadataProvider metadataProvider,
    String module,
  ) async =>
      _addBasePath((await metadataProvider.moduleToModulePath)[module] ?? '');

  Future<String> _sourceMapPathForModule(
    MetadataProvider metadataProvider,
    String module,
  ) async =>
      _addBasePath((await metadataProvider.moduleToSourceMap)[module] ?? '');

  String? _serverPathForAppUri(String appUrl) {
    final appUri = Uri.parse(appUrl);
    if (appUri.isScheme('org-dartlang-app')) {
      return _addBasePath(appUri.path);
    }
    if (appUri.isScheme('package')) {
      final resolved = _packageUriMapper.packageUriToServerPath(appUri);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  Future<Map<String, ModuleInfo>> _moduleInfoForProvider(
    MetadataProvider metadataProvider,
  ) async {
    final modules = await metadataProvider.moduleToModulePath;
    final result = <String, ModuleInfo>{};
    for (final module in modules.keys) {
      final modulePath = modules[module]!;
      result[module] = ModuleInfo(
        // TODO: Save locations of full kernel files in ddc metadata.
        // Issue: https://github.com/dart-lang/sdk/issues/43684
        p.setExtension(modulePath, '.full.dill'),
        p.setExtension(modulePath, '.dill'),
      );
    }
    return result;
  }
}

/// Provides a [DdcStrategy] suitable for use with Frontend Server.
class FrontendServerDdcStrategyProvider
    extends FrontendServerStrategyProvider<DdcStrategy> {
  late final DdcStrategy _ddcStrategy = DdcStrategy(
    _configuration,
    _moduleProvider,
    (_) => _digestsProvider(),
    _moduleForServerPath,
    _serverPathForModule,
    _sourceMapPathForModule,
    _serverPathForAppUri,
    _moduleInfoForProvider,
    _assetReader,
    _buildSettings,
    (String _) => null,
    packageConfigPath: _packageConfigPath,
  );

  FrontendServerDdcStrategyProvider(
    super._configuration,
    super._assetReader,
    super._packageUriMapper,
    super._digestsProvider,
    super._buildSettings, {
    super.packageConfigPath,
  });

  @override
  DdcStrategy get strategy => _ddcStrategy;
}

/// Provides a [DdcLibraryBundleStrategy] for the Frontend Server-only
/// configuration.
class FrontendServerDdcLibraryBundleStrategyProvider
    extends FrontendServerStrategyProvider<DdcLibraryBundleStrategy> {
  late final DdcLibraryBundleStrategy _libraryBundleStrategy;

  FrontendServerDdcLibraryBundleStrategyProvider(
    super._configuration,
    super._assetReader,
    super._packageUriMapper,
    super._digestsProvider,
    super._buildSettings, {
    super.packageConfigPath,
    Uri? reloadedSourcesUri,
    bool injectScriptLoad = true,
  }) {
    _libraryBundleStrategy = DdcLibraryBundleStrategy(
      _configuration,
      _moduleProvider,
      (_) => _digestsProvider(),
      _moduleForServerPath,
      _serverPathForModule,
      _sourceMapPathForModule,
      _serverPathForAppUri,
      _moduleInfoForProvider,
      _assetReader,
      _buildSettings,
      (String _) => null,
      packageConfigPath: _packageConfigPath,
      reloadedSourcesUri: reloadedSourcesUri,
      injectScriptLoad: injectScriptLoad,
    );
  }

  @override
  DdcLibraryBundleStrategy get strategy => _libraryBundleStrategy;
}

/// Provides a [DdcLibraryBundleStrategy] for the Frontend Server + Build
/// Daemon configuration, which supports hot reload.
class FrontendServerBuildDaemonStrategyProvider
    extends FrontendServerStrategyProvider<DdcLibraryBundleStrategy> {
  late final DdcLibraryBundleStrategy _libraryBundleStrategy;

  FrontendServerBuildDaemonStrategyProvider(
    super._configuration,
    super._assetReader,
    super._packageUriMapper,
    super._digestsProvider,
    super._buildSettings, {
    super.packageConfigPath,
    Uri? reloadedSourcesUri,
    bool injectScriptLoad = true,
  }) {
    String stripPrefix(String path) {
      if (path.startsWith('packages')) return path;
      final parts = path.split('/');
      
      final appUri = _buildSettings.appEntrypoint;
      final validPrefixes = [
        if (appUri != null && appUri.pathSegments.isNotEmpty)
          appUri.pathSegments.first,
        ..._defaultWebDirs,
      ];

      if (parts.length > 1 && validPrefixes.contains(parts[0])) {
        return parts.skip(1).join('/');
      }
      return path;
    }

    _libraryBundleStrategy = DdcLibraryBundleStrategy(
      _configuration,
      _moduleProvider,
      (_) => _digestsProvider(),
      /// Looks up the module name for a given server path.
      (metadataProvider, sourcePath) async {
        var module = await _moduleForServerPath(metadataProvider, sourcePath);
        if (module != null) return module;

        final remappedPath = sourcePath.replaceAll('.ddc', '.dart.lib');
        module = await _moduleForServerPath(metadataProvider, remappedPath);
        if (module != null) return module;

        final modulePathToModule = await metadataProvider.modulePathToModule;
        for (final entry in modulePathToModule.entries) {
          final key = entry.key;
          final strippedKey = stripPrefix(key);
          if (strippedKey == sourcePath || strippedKey == remappedPath) {
            return entry.value;
          }
        }
        return null;
      },
      (metadataProvider, module) async {
        final path = await _serverPathForModule(metadataProvider, module);
        final stripped = stripPrefix(path);
        return stripped.replaceAll('.dart.lib', '.ddc');
      },
      (metadataProvider, module) async {
        final path = await _sourceMapPathForModule(metadataProvider, module);
        final stripped = stripPrefix(path);
        return stripped.replaceAll('.dart.lib', '.ddc');
      },
      (appUrl) {
        final appUri = Uri.parse(appUrl);
        if (appUri.isScheme('org-dartlang-app')) {
          final segments = appUri.pathSegments;
          if (segments.length > 2 &&
              segments[0] == segments[1] &&
              (segments[0] == 'web' || segments[0] == 'test')) {
            return segments.skip(2).join('/');
          }
          return segments.skip(1).join('/');
        }
        return _serverPathForAppUri(appUrl);
      },
      (metadataProvider) async {
        final moduleInfo = await _moduleInfoForProvider(metadataProvider);
        return moduleInfo.map((module, info) {
          return MapEntry(
            module,
            ModuleInfo(
              info.fullDillPath.replaceAll('.dart.lib', '.ddc'),
              info.summaryPath.replaceAll('.dart.lib', '.ddc'),
            ),
          );
        });
      },
      _assetReader,
      _buildSettings,
      (String _) => null,
      packageConfigPath: _packageConfigPath,
      reloadedSourcesUri: reloadedSourcesUri,
      injectScriptLoad: injectScriptLoad,
    );
  }

  @override
  DdcLibraryBundleStrategy get strategy => _libraryBundleStrategy;
}

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider
    extends FrontendServerStrategyProvider<RequireStrategy> {
  late final RequireStrategy _requireStrategy = RequireStrategy(
    _configuration,
    _moduleProvider,
    (_) => _digestsProvider(),
    _moduleForServerPath,
    _serverPathForModule,
    _sourceMapPathForModule,
    _serverPathForAppUri,
    _moduleInfoForProvider,
    _assetReader,
    _buildSettings,
    packageConfigPath: _packageConfigPath,
  );

  FrontendServerRequireStrategyProvider(
    super._configuration,
    super._assetReader,
    super._packageUriMapper,
    super._digestsProvider,
    super._buildSettings, {
    super.packageConfigPath,
  });

  @override
  RequireStrategy get strategy => _requireStrategy;
}
