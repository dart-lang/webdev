// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class ExpressionCompilationResult {
  final bool isError;
  final String result;

  ExpressionCompilationResult(this.result, this.isError);
}

/// Interface to provide means of compiling expressions from dart to JavaScript,
/// used to implement expression evaluation in any tools using dwds
abstract class ExpressionCompiler {
  /// Compiles [expression] in [libraryUri] at[line]:[column] to javascript
  /// in [moduleName].
  ///
  /// Values listed in [jsFrameValues] are substituted for their names in the
  /// [expression].
  ///
  /// Ensures that all [jsModules] are loaded and accessible inside the
  /// expression.
  ///
  /// Returns ExpressionCompilationResult containting expression compiled to
  /// javascript or null on error, and an isError status.
  /// Errors are reported using onDiagnostic function
  /// [moduleName] is of the form '/packages/hello_world_main.dart'
  /// [jsFrameValues] is a map from js variable name to its primitive value
  /// or another variable name, for example
  /// { 'x': '1', 'y': 'y', 'o': 'null' }
  /// [jsModules] is a map from variable name to the module name, where
  /// variable name is the name originally used in javascript to contain the
  /// module object, for example:
  /// { 'dart':'dart_sdk', 'main': '/packages/hello_world_main.dart' }
  Future<ExpressionCompilationResult> compileExpressionToJs(
      String isolateId,
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression);
}
