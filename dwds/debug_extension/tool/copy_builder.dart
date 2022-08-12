// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';

/// Factory for the build script.
Builder copyBuilder(_) => _CopyBuilder();

class _CopyBuilder extends Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        "web/{{}}.dart.js": ["build/web_prod/{{}}.js"],
        "web/{{}}.png": ["build/web_prod/{{}}.png"],
        "web/{{}}.html": ["build/web_prod/{{}}.html"],
        "web/{{}}.css": ["build/web_prod/{{}}.css"],
        "web/manifest_prod.json": ["build/web_prod/manifest.json"],
        "web/panel.js": ["build/web_prod/panel.js"],
        "web/detector.js": ["build/web_prod/detector.js"],
        "web/devtools.js": ["build/web_prod/devtools.js"],
      };

  @override
  void build(BuildStep buildStep) {
    final inputAsset = buildStep.inputId;
    final allowedOutputs = buildStep.allowedOutputs;

    if (allowedOutputs.isEmpty) {
      print('Skipping ${inputAsset.path} which has no output options.');
      return;
    } else if (allowedOutputs.length > 1) {
      print('Skipping ${inputAsset.path} which has multiple output options.');
      return;
    }

    final outputAsset = allowedOutputs.first;
    if (outputAsset.path.endsWith('.png')) {
      _copyBinaryFile(buildStep,
          inputAsset: inputAsset, outputAsset: outputAsset);
    } else {
      _copyTextFile(buildStep,
          inputAsset: inputAsset, outputAsset: outputAsset);
    }
  }

  void _copyTextFile(
    BuildStep buildStep, {
    required AssetId inputAsset,
    required AssetId outputAsset,
  }) {
    buildStep.writeAsString(outputAsset, buildStep.readAsString(inputAsset));
  }

  void _copyBinaryFile(
    BuildStep buildStep, {
    required AssetId inputAsset,
    required AssetId outputAsset,
  }) {
    buildStep.writeAsBytes(outputAsset, buildStep.readAsBytes(inputAsset));
  }
}
