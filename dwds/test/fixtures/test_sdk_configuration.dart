// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO:(annagrin) Move to a test_common package.
import 'package:dwds/src/utilities/sdk_configuration.dart';

import 'sdk_asset_generator.dart';
import 'test_sdk_layout.dart';

/// Implementation for SDK configuration for tests that can generate
/// missing assets.
///
///  - Generate SDK js, source map, and full dill for weak and sound
///    modes (normally included in flutter SDK or produced by build).
///  - Need to generate SDK summary for weak null safety mode as it
///    is not provided by the SDK installation.
///
/// TODO(annagrin): update to only generating missing sound artifacts
/// for frontend server after we have no uses of weak null safety.
class TestSdkConfigurationProvider extends SdkConfigurationProvider {
  final bool _verboseCompiler;
  SdkConfiguration? _configuration;

  final sdkLayout = TestSdkLayout.defaultSdkLayout;

  TestSdkConfigurationProvider({bool verboseCompiler = false})
      : _verboseCompiler = verboseCompiler;

  @override
  Future<SdkConfiguration> get configuration async =>
      _configuration ??= await _create();

  /// Generate missing assets in the default SDK layout.
  Future<SdkConfiguration> _create() async {
    final assetGenerator = SdkAssetGenerator(
      sdkLayout: sdkLayout,
      verboseCompiler: _verboseCompiler,
    );

    await assetGenerator.generateSdkAssets();
    return TestSdkLayout.defaultSdkConfiguration;
  }
}
