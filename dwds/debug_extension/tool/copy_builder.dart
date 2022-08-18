// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

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
        "web/manifest.json": ["build/web_prod/manifest.json"],
        "web/panel.js": ["build/web_prod/panel.js"],
        "web/detector.js": ["build/web_prod/detector.js"],
        "web/devtools.js": ["build/web_prod/devtools.js"],
      };

  @override
  void build(BuildStep buildStep) async {
    final inputAsset = buildStep.inputId;
    final allowedOutputs = buildStep.allowedOutputs;

    if (allowedOutputs.length != 1) {
      return;
    }

    final outputAsset = allowedOutputs.first;
    await _copyBinaryFile(buildStep,
        inputAsset: inputAsset, outputAsset: outputAsset);

    if (outputAsset.path.endsWith('manifest.json')) {
      await _maybeAddExtensionKey(outputAsset.path);
    }
  }

  Future<void> _copyBinaryFile(
    BuildStep buildStep, {
    required AssetId inputAsset,
    required AssetId outputAsset,
  }) {
    return buildStep.writeAsBytes(outputAsset, buildStep.readAsBytes(inputAsset));
  }

  Future<void> _maybeAddExtensionKey(String manifestJsonPath) async {
    final manifestJson = File(manifestJsonPath);
    final extensionKey = File('extension_key.txt');
    if (await extensionKey.exists()) {
      return _addExtensionKey(manifestJson, extensionKey);
    }
    return null;
  }

  Future<void> _addExtensionKey(File manifestJson, File extensionKey) async {
    final lines = manifestJson.readAsLinesSync();
    final newLines = <String>[];

    for (final line in lines) {
      newLines.add(line);
      if (line.trim().startsWith('"name":')) {
        final keyValue = await extensionKey.readAsString();
        newLines.add('    "key": "$keyValue",');
      }
    }

    final content = newLines.joinWithNewLine();
    return manifestJson.writeAsStringSync(content);
  }
}

extension JoinExtension on List<String> {
  String joinWithNewLine() {
    return '${join('\n')}\n';
  }
}
