// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/strategy.dart';

class DartRuntimeDebugger {
  final LoadStrategy _loadStrategy;
  final bool _useLibraryBundleExpression;

  DartRuntimeDebugger({
    required LoadStrategy loadStrategy,
    required bool useLibraryBundleExpression,
  })  : _loadStrategy = loadStrategy,
        _useLibraryBundleExpression = useLibraryBundleExpression;

  /// Generates a JS expression based on DDC module format.
  String _generateJsExpression(
    String ddcExpression,
    String libraryBundleExpression,
  ) {
    return _useLibraryBundleExpression
        ? libraryBundleExpression
        : ddcExpression;
  }

  /// Wraps a JS function call with SDK loader logic.
  String _wrapWithSdkLoader(String args, String functionCall) {
    return '''
      function($args) {
        const sdk = ${_loadStrategy.loadModuleSnippet}('dart_sdk');
        const dart = sdk.dart;
        return dart.$functionCall;
      }
    ''';
  }

  /// Wraps a JS function call with DDC library bundle loader logic.
  String _wrapWithBundleLoader(String args, String functionCall) {
    return '''
      function($args) {
        return dartDevEmbedder.debugger.$functionCall;
      }
    ''';
  }

  /// Wraps an expression in an Immediately Invoked Function Expression (IIFE).
  String _wrapInIIFE(String expression) {
    return '($expression)()';
  }

  /// Builds a JS expression based on the loading strategy.
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

  /// Generates a JS expression for retrieving object metadata.
  String getObjectMetadataJsExpression() {
    return _buildExpression(
      'arg',
      'getObjectMetadata(arg)',
      'getObjectMetadata(arg)',
    );
  }

  /// Generates a JS expression for retrieving object field names.
  String getObjectFieldNamesJsExpression() {
    return _buildExpression(
      '',
      'getObjectFieldNames(this)',
      'getObjectFieldNames(this)',
    );
  }

  /// Generates a JS expression for retrieving function metadata.
  String getFunctionMetadataJsExpression() {
    return _buildExpression(
      '',
      'getFunctionMetadata(this)',
      'getFunctionName(this)',
    );
  }

  /// Generates a JS expression for retrieving a subrange of elements.
  String getSubRangeJsExpression() {
    return _buildExpression(
      'offset, count',
      'getSubRange(this, offset, count)',
      'getSubRange(this, offset, count)',
    );
  }

  /// Generates a JS expression for retrieving class metadata.
  String getClassMetadataJsExpression(String libraryUri, String className) {
    final expression = _buildExpression(
      '',
      "getClassMetadata('$libraryUri', '$className')",
      "getClassMetadata('$libraryUri', '$className')",
    );
    // Use the helper method to wrap this in an IIFE
    return _wrapInIIFE(expression);
  }
}
