// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

void main() async {
  await _updateManifestJson();
}

/// Adds the Googler extension key, and prefixes the extension name with "DEV".
Future<void> _updateManifestJson() async {
  final manifestJson = File('compiled/manifest.json');
  final extensionKeyTxt = File('extension_key.txt');
  final extensionKey = await extensionKeyTxt.exists()
      ? await extensionKeyTxt.readAsString()
      : null;
  return _transformDevFile(manifestJson, (line) {
    if (_matchesKey(line: line, key: 'name')) {
      return [
        _newKeyValue(
          oldLine: line,
          newKey: 'name',
          newValue: '[DEV] Dart Debug Extension',
        ),
        if (extensionKey != null)
          _newKeyValue(
            oldLine: line,
            newKey: 'key',
            newValue: extensionKey,
          ),
      ];
    } else if (_matchesKey(line: line, key: 'default_icon')) {
      return [
        _newKeyValue(
          oldLine: line,
          newKey: 'default_icon',
          newValue: 'static_assets/dart_dev.png',
        ),
      ];
    } else {
      return [line];
    }
  });
}

Future<void> _transformDevFile(
  File devFile,
  List<String> Function(String) transformLine,
) async {
  final lines = devFile.readAsLinesSync();
  final newLines = <String>[];
  for (final line in lines) {
    newLines.addAll(transformLine(line));
  }
  final content = newLines.joinWithNewLine();
  return devFile.writeAsStringSync(content);
}

bool _matchesKey({required String line, required String key}) {
  return line.trimLeft().startsWith('"$key":');
}

String _newKeyValue({
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
