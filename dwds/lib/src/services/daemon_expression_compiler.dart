// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/src/services/expression_compiler.dart';

/// An expression compiler that forwards expression compilation requests to the
/// build daemon.
///
/// We assume the build daemon already has a Frontend Server intialized.
final class DaemonExpressionCompiler implements ExpressionCompiler {
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> request)
  _sendRequest;

  DaemonExpressionCompiler(this._sendRequest);

  @override
  Future<ExpressionCompilationResult> compileExpressionToJs(
    String isolateId,
    String libraryUri,
    String scriptUri,
    int line,
    int column,
    Map<String, String> jsModules,
    Map<String, String> jsFrameValues,
    String moduleName,
    String expression,
  ) async {
    final requestJson = {
      'instruction': 'COMPILE_EXPRESSION_JS',
      'isolateId': isolateId,
      'libraryUri': libraryUri,
      'scriptUri': scriptUri,
      'line': line,
      'column': column,
      'jsModules': jsModules,
      'jsFrameValues': jsFrameValues,
      'moduleName': moduleName,
      'expression': expression,
    };
    final responseJson = await _sendRequest(requestJson);
    final expressionDataString = responseJson['expressionData'] as String?;
    final errorMessage = responseJson['errorMessage'] as String?;
    final errorCount = responseJson['errorCount'] as int? ?? 0;

    final isError = errorCount > 0 || expressionDataString == null;

    String result;
    if (isError) {
      result = errorMessage ?? 'Unknown compilation error';
    } else {
      final bytes = base64.decode(expressionDataString);
      result = utf8.decode(bytes);
    }

    return ExpressionCompilationResult(result, isError);
  }

  /// Not needed by [DaemonExpressionCompiler] since we assume that a shared
  /// Frontend Server instance is already initialized.
  @override
  Future<void> initialize(CompilerOptions options) async {}

  /// Not needed by [DaemonExpressionCompiler] since reloads are handled by
  /// `reloaded_sources.json`, which are generated from build daemon's build
  /// outputs.
  @override
  Future<bool> updateDependencies(Map<String, ModuleInfo> modules) async =>
      true;
}
