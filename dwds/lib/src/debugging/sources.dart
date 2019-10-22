// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';

import '../../asset_handler.dart';
import '../../dwds.dart' show LogWriter;

/// Paths to black box in the Chrome debugger.
const pathsToBlackBox = {'/packages/stack_trace/'};

/// The scripts and sourcemaps for the application, both JS and Dart.
class Sources {
  final AssetHandler _assetHandler;
  final LogWriter _logWriter;

  Sources(this._assetHandler, this._logWriter);

  /// Reads an asset at [path] relative to the server root.
  ///
  /// Returns `null` and logs the response if the status is anything other than
  /// [HttpStatus.ok].
  Future<String> readAssetOrNull(String path) async {
    var response = await _assetHandler.getRelativeAsset(path);
    var responseText = '';
    var hasError = false;
    try {
      responseText = await response.readAsString();
    } on ClientException {
      hasError = true;
      responseText = '<response not available>';
    }
    if (response.statusCode == HttpStatus.ok && !hasError) {
      return responseText;
    } else {
      _logWriter(Level.WARNING, '''
      Failed to load asset at path: $path.

      Status code: ${response.statusCode}

      Headers:
      ${const JsonEncoder.withIndent('  ').convert(response.headers)}

      Content:
      $responseText}
      ''');
      return null;
    }
  }
}
