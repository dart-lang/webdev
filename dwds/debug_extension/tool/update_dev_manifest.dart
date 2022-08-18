// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

/// Adds the extension key and updates the icon in the manifest.json.
void main() async {
  final manifestJson = File('dev_build/web/manifest.json');
  final extensionKey = File('extension_key.txt');
  final keyValue =
      await extensionKey.exists() ? await extensionKey.readAsString() : null;
  _updateManifest(manifestJson, extensionKey: keyValue);
}

Future<void> _updateManifest(File manifestJson, {String? extensionKey}) async {
  final lines = manifestJson.readAsLinesSync();
  final newLines = <String>[];
  for (final line in lines) {
    final trimmedLine = line.trimLeft();
    if (trimmedLine.startsWith('"name":') && extensionKey != null) {
      newLines.add(line);
      newLines.add('${line.leftPadding()}"key": "$extensionKey",');
    } else if (trimmedLine.startsWith('"default_icon":')) {
      newLines.add('${line.leftPadding()}"default_icon": "dart_dev.png"');
    } else {
      newLines.add(line);
    }
  }
  final content = newLines.joinWithNewLine();
  return manifestJson.writeAsStringSync(content);
}

extension LeftPaddingExtension on String {
  String leftPadding() {
    String padding = '';
    int idx = 0;
    while (idx < length && this[idx] == ' ') {
      padding += ' ';
      idx++;
    }
    return padding;
  }
}

extension JoinExtension on List<String> {
  String joinWithNewLine() {
    return '${join('\n')}\n';
  }
}
