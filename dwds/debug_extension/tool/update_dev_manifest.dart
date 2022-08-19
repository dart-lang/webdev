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
    if (matchesKey(line: line, key: 'name')) {
      newLines.add(
        newLine(
          oldLine: line,
          newKey: 'name',
          newValue: '[DEV] Dart Debug Extension',
        ),
      );
      if (extensionKey != null) {
        newLines.add(
          newLine(
            oldLine: line,
            newKey: 'key',
            newValue: extensionKey,
          ),
        );
      }
    } else if (matchesKey(line: line, key: 'default_icon')) {
      newLines.add(
        newLine(
          oldLine: line,
          newKey: 'default_icon',
          newValue: 'dart_dev.png',
        ),
      );
    } else if (matchesValue(line: line, value: 'background.js')) {
      newLines.add(
        newLine(
          oldLine: line,
          newKey: null,
          newValue: 'background.dart.js',
        ),
      );
    } else {
      newLines.add(line);
    }
  }
  final content = newLines.joinWithNewLine();
  return manifestJson.writeAsStringSync(content);
}

bool matchesKey({required String line, required String key}) {
  return line.trimLeft().startsWith('"$key":');
}

bool matchesValue({required String line, required String value}) {
  return line.trimRight().endsWith('"$value"') ||
      line.trimRight().endsWith('"$value",');
}

String newLine({
  required String oldLine,
  String? newKey,
  String? newValue,
}) {
  final lineStart = oldLine.leftPadding();
  final key = newKey != null ? '"$newKey": ' : '';
  final value = newValue != null ? '"$newValue"' : '';
  final lineEnd = oldLine.trim().endsWith(',') ? ',' : '';
  return '$lineStart$key$value$lineEnd';
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
