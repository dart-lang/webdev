// Copyright 2023 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:path/path.dart' as p;

abstract class FrontendServerStrategyProvider<T> {
  final ReloadConfiguration configuration;
  final AssetReader assetReader;
  final PackageUriMapper packageUriMapper;
  final Future<Map<String, String>> Function() digestsProvider;
  final String basePath;
  final BuildSettings buildSettings;

  FrontendServerStrategyProvider(
    this.configuration,
    this.assetReader,
    this.packageUriMapper,
    this.digestsProvider,
    this.buildSettings,
  ) : basePath = assetReader.basePath;

  T get strategy;

  String removeBasePath(String path) {
    if (basePath.isEmpty) return path;
    final stripped = stripLeadingSlashes(path);
    return stripLeadingSlashes(stripped.substring(basePath.length));
  }

  String addBasePath(String serverPath) => basePath.isEmpty
      ? stripLeadingSlashes(serverPath)
      : '$basePath/${stripLeadingSlashes(serverPath)}';

  String removeJsExtension(String path) =>
      path.endsWith('.js') ? p.withoutExtension(path) : path;

  Future<Map<String, String>> moduleProvider(
    MetadataProvider metadataProvider,
  ) async =>
      (await metadataProvider.moduleToModulePath).map(
        (key, value) =>
            MapEntry(key, stripLeadingSlashes(removeJsExtension(value))),
      );

  Future<String?> moduleForServerPath(
    MetadataProvider metadataProvider,
    String serverPath,
  ) async {
    final modulePathToModule = await metadataProvider.modulePathToModule;
    final relativeServerPath = removeBasePath(serverPath);
    return modulePathToModule[relativeServerPath];
  }

  Future<String> serverPathForModule(
    MetadataProvider metadataProvider,
    String module,
  ) async =>
      addBasePath((await metadataProvider.moduleToModulePath)[module] ?? '');

  Future<String> sourceMapPathForModule(
    MetadataProvider metadataProvider,
    String module,
  ) async =>
      addBasePath((await metadataProvider.moduleToSourceMap)[module] ?? '');

  String? serverPathForAppUri(String appUrl) {
    final appUri = Uri.parse(appUrl);
    if (appUri.isScheme('org-dartlang-app')) {
      return addBasePath(appUri.path);
    }
    if (appUri.isScheme('package')) {
      final resolved = packageUriMapper.packageUriToServerPath(appUri);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  Future<Map<String, ModuleInfo>> moduleInfoForProvider(
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
