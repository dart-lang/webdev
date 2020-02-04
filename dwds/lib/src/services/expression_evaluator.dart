// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/utilities/objects.dart' as chrome;
import 'package:dwds/src/utilities/shared.dart' show LogWriter;
import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'expression_compiler.dart';

/// ExpressionEvaluator provides functionality to evaluate dart expressions
/// from text user input in the debugger, using chrome remote debugger to
/// collect context for evaluation (scope, types, modules), and using
/// ExpressionCompilerInterface to compile dart expressions to JavaScript.
class ExpressionEvaluator {
  final Debugger _debugger;
  final Locations _locations;
  final Modules _modules;
  final ExpressionCompiler _compiler;
  final LogWriter _logWriter;

  ExpressionEvaluator(this._debugger, this._locations, this._modules,
      this._compiler, this._logWriter);

  void _printTrace(String message) {
    _logWriter(Level.INFO, message);
  }

  RemoteObject _createError(String severity, String message) {
    return RemoteObject(
        <String, dynamic>{'type': 'string', 'value': '$severity: $message'});
  }

  /// Evaluate dart expression inside a given JavaScript frame (function)
  ///
  /// Gets necessary context (types, scope, module names) data from chrome,
  /// uses ExpressionCompiler interface to compile the expression to JavaScript,
  /// and sends evaluate requests to chrome to calculate the final result.
  ///
  /// Returns remote object containing the result of evaluation or error
  /// [isolateId] not used
  /// [frameIndex] JavaScript frame to evaluate the expression in
  /// [expression] dart expression to evaluate
  Future<RemoteObject> evaluateExpression(
      String isolateId, int frameIndex, String expression) async {
    if (_compiler == null) {
      return _createError(
          'Internal error', 'ExpressionEvaluator needs an ExpressionCompiler');
    }

    if (expression == null || expression.isEmpty) {
      return _createError('Invalid input', expression);
    }

    // 1. get js scope and current JS location

    var jsStack = _debugger.getJsStack();
    var jsFrame = chrome.CallFrame(jsStack[frameIndex]);

    var functionName = jsFrame.functionName;
    var jsLocation = jsFrame.location;
    _printTrace('Expression evaluator: JS location: '
        '$functionName, $jsLocation');

    var jsScope = await _collectLocalJsScope(jsFrame);
    _printTrace('Expression evaluator: Local JS Scope: $jsScope');

    // 2. find corresponding dart location and scope

    var locationMap = await _locations.locationForJs(
        jsLocation.scriptId, jsLocation.lineNumber);

    if (locationMap == null) {
      return _createError(
          'Internal Error',
          'cannot find Dart location for JS location '
              '{script: $jsLocation.scriptId, '
              'function: $functionName, '
              'location: $jsLocation})');
    }

    var dartLocation = locationMap.dartLocation;
    var packageUri =
        await _modules.packageForSource(dartLocation.uri.serverPath);

    _printTrace('Expression evaluator: dart Location: '
        '$packageUri:${dartLocation.line}:${dartLocation.column}');

    // TODO(annagrin): figure out what modules to require for given expression
    var currentModule =
        await _modules.moduleForSource(dartLocation.uri.serverPath);
    var modules = <String>{currentModule};

    var jsModules = {'dart': 'dart_sdk', 'core': 'dart_sdk'};
    for (var module in modules) {
      var name = module.split('/').last;
      jsModules[name] = module;
    }
    _printTrace('Expression evaluator: js modules: $jsModules');

    var compilationResult = await _compiler.compileExpressionToJs(
        isolateId,
        packageUri,
        dartLocation.line,
        dartLocation.column,
        jsModules,
        jsScope,
        currentModule,
        expression);

    // 5. send js expression to chrome to evaluate

    var isError = compilationResult.isError;
    var jsExpression = compilationResult.result;

    _printTrace('Expression evaluator: js: $jsExpression, isError: $isError');

    // TODO(annagrin): modify frontend to avoid stripping dummy names
    if (isError) {
      var error = jsExpression
          .replaceAll(r'[', '')
          .replaceAll(r']', '')
          .replaceAll(r'org-dartlang-debug:synthetic_debug_expression:', '');

      return _createError('Compilation error', error);
    }

    var result =
        await _debugger.evaluateJsOnCallFrameIndex(frameIndex, jsExpression);

    _printTrace('Expression evaluator: '
        'Evaluation result returned from chrome: $result');

    // 6. Return evaluation result or error
    return result;
  }

  String _valueToLiteral(RemoteObject value) {
    var ret = value.value.toString();
    if (value.type == 'string') {
      return '\'$ret\'';
    }

    return ret;
  }

  Future<Map<String, String>> _collectLocalJsScope(
      chrome.CallFrame frame) async {
    var jsScope = <String, String>{};

    void collectVariables(String scopeName, Iterable<chrome.Property> variables,
        String scopeType) {
      for (var p in variables) {
        var name = p.name;
        var value = p.value;

        if (scopeType == 'closure') {
          // substitute potentially unavailable captures with their values from
          // the stack.
          //
          // Note: this makes some uncaptured values available for evaluation,
          // which might not be formally correct but convenient, for evample:
          //
          // int x = 0;
          // var f = (int y) {
          //   // 'x' is not captured so it not available at runtime but is
          //   // captured on stack, so the code below will make it available
          //   // for evaluation
          //   print(y);
          // }
          // TODO(annagrin): decide if we would like not to support evaluation
          // of upcaptured variables
          jsScope[name] = _valueToLiteral(value);
        }
        if (scopeType == 'local') {
          jsScope[name] = name;
        }
      }
    }

    var scopeChain = frame.scopeChain;
    for (var scope in scopeChain.innerScopes) {
      var scopeProperties =
          await _debugger.getProperties(scope.object.objectId);
      collectVariables(scope.name, scopeProperties, scope.type);
    }

    return jsScope;
  }
}
