// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/utilities/objects.dart' as objects;
import 'package:dwds/src/utilities/shared.dart' show LogWriter;
import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'expression_compiler.dart';

class ExpressionEvaluator {
  final Future<Debugger> _debugger;
  final Locations _locations;
  final Modules _modules;
  final ExpressionCompilerInterface _compiler;
  final LogWriter _logWriter;

  ExpressionEvaluator(this._debugger, this._locations, this._modules,
      this._compiler, this._logWriter);

  void printTrace(String message) {
    _logWriter(Level.INFO, message);
  }

  RemoteObject _createError(String severity, String message) {
    return RemoteObject(
        <String, dynamic>{'type': 'string', 'value': '$severity: $message'});
  }

  Future<RemoteObject> evaluateExpression(
      String isolateId, int frameIndex, String expression) async {
    if (_compiler == null) {
      return _createError('Internal error',
          'Expression evaluation is only supported with frontend server');
    }

    if (expression == null || expression.isEmpty) {
      return _createError('Invalid input', expression);
    }

    var debugger = await _debugger;

    // 1. get js scope and current JS location

    var jsStack = debugger.getJsStack();
    var jsFrame = objects.Frame(jsStack[frameIndex]);

    var functionName = jsFrame.functionName;
    var jsLocation = jsFrame.location;
    printTrace('Expression evaluator: JS location: '
        '$functionName, $jsLocation');

    var jsScope = await _collectLocalJsScope(jsFrame);
    printTrace('Expression evaluator: Local JS Scope: $jsScope');

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

    printTrace('Expression evaluator: dart Location: '
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
    printTrace('Expression evaluator: js modules: $jsModules');

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

    printTrace('Expression evaluator: js: $jsExpression, isError: $isError');

    if (isError) {
      var error = jsExpression
          .replaceAll(r'[', '')
          .replaceAll(r']', '')
          .replaceAll(r'org-dartlang-debug:synthetic_debug_expression:', '');

      return _createError('Compilation error', error);
    }

    var result =
        await debugger.evaluateJsOnCallFrameIndex(frameIndex, jsExpression);

    printTrace('Expression evaluator: '
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

  Future<Map<String, String>> _collectLocalJsScope(objects.Frame frame) async {
    var jsScope = <String, String>{};

    void collectVariables(String scopeName,
        Iterable<objects.Property> variables, String scopeType) {
      for (var p in variables) {
        var name = p.name;
        var value = p.value;

        if (scopeType == 'closure') {
          // substitute potentially unavailable captures with their values from
          // the stack.
          //
          // Note: this makes some uncaptured values available for evaluation,
          // which might be not formally correct but convenient, for evample:
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
          await (await _debugger).getProperties(scope.object.objectId);
      collectVariables(scope.name, scopeProperties, scope.type);
    }

    return jsScope;
  }
}
