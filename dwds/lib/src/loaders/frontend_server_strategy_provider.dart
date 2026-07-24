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
import 'package:dwds/src/utilities/ddc_uri_translator.dart';
import 'package:path/path.dart' as p;

abstract class FrontendServerStrategyProvider<T extends LoadStrategy> {
  final ReloadConfiguration _configuration;
  final AssetReader _assetReader;
  final Future<Map<String, String>> Function() _digestsProvider;
  final String _basePath;
  final BuildSettings _buildSettings;
  final String? _packageConfigPath;

  FrontendServerStrategyProvider(
    this._configuration,
    this._assetReader,
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
    final translated = DdcUriTranslator.translateAppUriToServerPath(
      appUrl,
      layout: AppUriLayout.frontendServerOnly,
      useDebuggerModuleNames: _buildSettings.useDebuggerModuleNames,
    );
    return translated != null ? _addBasePath(translated) : null;
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
  String? _serverPathForAppUri(String appUrl) {
    final isFlutterPackage =
        _buildSettings.isFlutterApp && appUrl.startsWith('package:');
    final layout = isFlutterPackage
        ? AppUriLayout.flutter
        : AppUriLayout.frontendServerOnly;
    final translated = DdcUriTranslator.translateAppUriToServerPath(
      appUrl,
      layout: layout,
      useDebuggerModuleNames: _buildSettings.useDebuggerModuleNames,
    );
    return translated != null ? _addBasePath(translated) : null;
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

  /// Strips the top-level web/entrypoint directory from a path.
  ///
  /// For example:
  /// - `web/main.dart` -> `main.dart`
  /// - `example/append_body/main.dart` -> `append_body/main.dart`
  /// - `packages/path/path.dart` -> `packages/path/path.dart` (unchanged)
  String _stripPrefix(String path) {
    path = path.replaceAll('\\', '/');
    if (path.startsWith('packages')) return path;
    final parts = path.split('/');

    final appUri = _buildSettings.appEntrypoint;
    final validPrefixes = [
      if (appUri != null && appUri.pathSegments.isNotEmpty)
        appUri.pathSegments.first,
      ...DdcUriTranslator.defaultWebDirs,
    ];

    if (parts.length > 1 && validPrefixes.contains(parts[0])) {
      return parts.skip(1).join('/');
    }
    return path;
  }

  /// Looks up the DDC module name for a served source file path while remapping
  /// browser-requested DDC paths (containing '.ddc') to Frontend Server-served
  /// paths (containing '.dart.lib').
  ///
  /// Requested paths can originate from different contexts at runtime, so we
  /// perform several runtime lookups:
  /// 1) Frontend Server uses '.dart.lib.js' and is referenced by expression
  ///    evaluation requests, metadata files, stack traces, and sourcemaps.
  /// 2) Build daemon serves with '.ddc.js' and is referenced by Chrome file
  ///    requests and Chrome DevTools protocol script URLs.
  @override
  Future<String?> _moduleForServerPath(
    MetadataProvider metadataProvider,
    String serverPath,
  ) async {
    final remappedPath = DdcUriTranslator.translateModuleExtension(
      serverPath,
      from: AppUriLayout.buildRunner,
      to: AppUriLayout.frontendServerOnly,
    );
    final module = await super._moduleForServerPath(
      metadataProvider,
      remappedPath,
    );
    if (module != null) return module;

    // Strip the top-level served directory prefix (e.g. 'web/') from root
    // modules to match the served path. Package dependencies ('packages/')
    // are not modified.
    final modulePathToModule = await metadataProvider.modulePathToModule;
    for (final entry in modulePathToModule.entries) {
      final strippedKey = _stripPrefix(entry.key);
      if (strippedKey == serverPath || strippedKey == remappedPath) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<String> _serverPathForModule(
    MetadataProvider metadataProvider,
    String module,
  ) async {
    final path = await super._serverPathForModule(metadataProvider, module);
    final stripped = _stripPrefix(path);
    return DdcUriTranslator.translateFesToBuildRunnerPath(stripped);
  }

  @override
  Future<String> _sourceMapPathForModule(
    MetadataProvider metadataProvider,
    String module,
  ) async {
    final path = await super._sourceMapPathForModule(metadataProvider, module);
    final stripped = _stripPrefix(path);
    return DdcUriTranslator.translateFesToBuildRunnerPath(stripped);
  }

  @override
  String? _serverPathForAppUri(String appUrl) =>
      DdcUriTranslator.translateAppUriToServerPath(
        appUrl,
        layout: AppUriLayout.buildRunner,
      );

  @override
  Future<Map<String, ModuleInfo>> _moduleInfoForProvider(
    MetadataProvider metadataProvider,
  ) async {
    final moduleInfo = await super._moduleInfoForProvider(metadataProvider);
    return moduleInfo.map((module, info) {
      return MapEntry(
        module,
        ModuleInfo(
          DdcUriTranslator.translateFesToBuildRunnerPath(info.fullDillPath),
          DdcUriTranslator.translateFesToBuildRunnerPath(info.summaryPath),
        ),
      );
    });
  }
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
    super._digestsProvider,
    super._buildSettings, {
    super.packageConfigPath,
  });

  @override
  String? _serverPathForAppUri(String appUrl) {
    final isFlutterPackage =
        _buildSettings.isFlutterApp && appUrl.startsWith('package:');
    final layout = isFlutterPackage
        ? AppUriLayout.flutter
        : AppUriLayout.frontendServerOnly;
    final translated = DdcUriTranslator.translateAppUriToServerPath(
      appUrl,
      layout: layout,
      useDebuggerModuleNames: _buildSettings.useDebuggerModuleNames,
    );
    return translated != null ? _addBasePath(translated) : null;
  }

  @override
  RequireStrategy get strategy => _requireStrategy;
}
