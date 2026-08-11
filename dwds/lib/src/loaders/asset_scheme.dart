// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Encapsulates asset file naming conventions and schemes.
abstract class AssetScheme {
  /// File extension for JS files.
  /// (e.g., '.ddc.js' or '.dart.lib.js').
  String get jsSuffix;

  /// File extension for sourcemaps.
  /// (e.g., '.ddc.js.map' or '.dart.lib.js.map').
  String get sourceMapSuffix;

  /// File extension for module names.
  /// (e.g., '.ddc' or '.dart.lib').
  String get descriptorSuffix;

  /// File extension for full dill files.
  /// (e.g., '.ddc.full.dill' or '.dart.lib.full.dill').
  String get fullDillSuffix;

  /// File extension for summary dill files.
  /// (e.g., '.ddc.dill' or '.dart.lib.dill').
  String get summaryDillSuffix;

  /// File extension for bootstrap files.
  /// (e.g., '.bootstrap.js' or '.dart.bootstrap.js').
  String get bootstrapSuffix;

  /// File extension for merged metadata.
  /// (e.g., '.ddc_merged_metadata').
  String get mergedMetadataSuffix;
}

/// Asset scheme for package:build assets.
final class BuildRunnerAssetScheme implements AssetScheme {
  const BuildRunnerAssetScheme();

  @override
  String get jsSuffix => '.ddc.js';

  @override
  String get sourceMapSuffix => '.ddc.js.map';

  @override
  String get descriptorSuffix => '.ddc';

  @override
  String get fullDillSuffix => '.ddc.full.dill';

  @override
  String get summaryDillSuffix => '.ddc.dill';

  @override
  String get bootstrapSuffix => '.bootstrap.js';

  @override
  String get mergedMetadataSuffix => '.ddc_merged_metadata';
}

/// Asset scheme for Frontend Server assets.
final class FrontendServerAssetScheme implements AssetScheme {
  const FrontendServerAssetScheme();

  @override
  String get jsSuffix => '.dart.lib.js';

  @override
  String get sourceMapSuffix => '.dart.lib.js.map';

  @override
  String get descriptorSuffix => '.dart.lib';

  @override
  String get fullDillSuffix => '.dart.lib.full.dill';

  @override
  String get summaryDillSuffix => '.dart.lib.dill';

  @override
  String get bootstrapSuffix => '.bootstrap.js';

  @override
  String get mergedMetadataSuffix => '.ddc_merged_metadata';
}
