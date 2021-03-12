// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

// Note: this is a copy from flutter tools, updated to work with dwds tests,
// most functionality removed

import 'dart:async';

import 'devfs_content.dart';

const AssetBundleFactory _manifestFactory = _MockManifestAssetBundleFactory();

const String defaultManifestPath = 'pubspec.yaml';

/// Injected factory class for spawning [AssetBundle] instances.
abstract class AssetBundleFactory {
  static AssetBundleFactory get defaultInstance => _manifestFactory;

  /// Creates a new [AssetBundle].
  AssetBundle createBundle();
}

abstract class AssetBundle {
  Map<String, DevFSContent> get entries;

  /// Returns 0 for success; non-zero for failure.
  Future<int> build({
    String manifestPath = defaultManifestPath,
    String assetDirPath,
    String packagesPath,
    bool includeDefaultFonts = true,
    bool reportLicensedPackages = false,
  });
}

class _MockManifestAssetBundleFactory implements AssetBundleFactory {
  const _MockManifestAssetBundleFactory();

  @override
  AssetBundle createBundle() => _MockManifestAssetBundle();
}

class _MockManifestAssetBundle implements AssetBundle {
  /// Constructs an [_MockManifestAssetBundle] that gathers the set of assets from the
  /// pubspec.yaml manifest.
  _MockManifestAssetBundle();

  @override
  final Map<String, DevFSContent> entries = <String, DevFSContent>{};

  @override
  Future<int> build({
    String manifestPath = defaultManifestPath,
    String assetDirPath,
    String packagesPath,
    bool includeDefaultFonts = true,
    bool reportLicensedPackages = false,
  }) async {
    return 0;
  }
}
