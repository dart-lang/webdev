// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/ddc_library_bundle.dart';
import 'package:dwds/src/loaders/strategy.dart';

class DartRuntimeDebugger {
  final LoadStrategy _loadStrategy;
  final bool _useLibraryBundleExpression;

  DartRuntimeDebugger(this._loadStrategy)
      : _useLibraryBundleExpression =
            _loadStrategy.runtimeType == DdcLibraryBundleStrategy;

  String _generateJsExpression(
    String ddcExpression,
    String libraryBundleExpression,
  ) {
    return _useLibraryBundleExpression
        ? libraryBundleExpression
        : ddcExpression;
  }

  String _wrapWithSdkLoader(String args, String functionCall) {
    return '''
      function($args) {
        const sdk = ${_loadStrategy.loadModuleSnippet}("dart_sdk");
        const dart = sdk.dart;
        return dart.$functionCall;
      }
    ''';
  }

  String _wrapWithBundleLoader(String args, String functionCall) {
    return '''
      function($args) {
        return dartDevEmbedder.debugger.$functionCall;
      }
    ''';
  }

  String _buildExpression(
    String args,
    String ddcFunction,
    String libraryBundleFunction,
  ) {
    return _generateJsExpression(
      _wrapWithSdkLoader(args, ddcFunction),
      _wrapWithBundleLoader(args, libraryBundleFunction),
    );
  }

  String getObjectMetadataJsExpression() {
    return _buildExpression(
      'arg',
      'getObjectMetadata(arg)',
      'getObjectMetadata(arg)',
    );
  }

  String getObjectFieldNamesJsExpression() {
    return _buildExpression(
      '',
      'getObjectFieldNames(this)',
      'getObjectFieldNames(this)',
    );
  }

  String getFunctionMetadataJsExpression() {
    return _buildExpression(
      '',
      'getFunctionMetadata(this)',
      'getFunctionName(this)',
    );
  }

  String getSubRangeJsExpression() {
    return _buildExpression(
      'offset, count',
      'getSubRange(this, offset, count)',
      'getSubRange(this, offset, count)',
    );
  }
}
