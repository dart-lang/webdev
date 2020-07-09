// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../debugging/dart_scope.dart';
import '../debugging/debugger.dart';
import '../debugging/location.dart';
import '../debugging/modules.dart';
import '../utilities/ddc_names.dart';
import '../utilities/objects.dart' as chrome;
import '../utilities/shared.dart' show LogWriter;
import 'expression_compiler.dart';

class ErrorKind {
  const ErrorKind._(this._kind);

  final String _kind;
  static const ErrorKind compilation = ErrorKind._('CompilationError');
  static const ErrorKind type = ErrorKind._('TypeError');
  static const ErrorKind reference = ErrorKind._('ReferenceError');
  static const ErrorKind internal = ErrorKind._('InternalError');
  static const ErrorKind invalidInput = ErrorKind._('InvalidInputError');

  @override
  String toString() => _kind;
}

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

  RemoteObject _createError(ErrorKind severity, String message) {
    return RemoteObject(
        <String, String>{'type': '$severity', 'value': message});
  }

  /// Evaluate dart expression inside a given JavaScript frame (function)
  ///
  /// Gets necessary context (types, scope, module names) data from chrome,
  /// uses ExpressionCompiler interface to compile the expression to JavaScript,
  /// and sends evaluate requests to chrome to calculate the final result.
  ///
  /// Returns remote object containing the result of evaluation or error
  /// [isolateId] current isolate ID
  /// [frameIndex] JavaScript frame to evaluate the expression in
  /// [expression] dart expression to evaluate
  Future<RemoteObject> evaluateExpression(
      String isolateId, int frameIndex, String expression) async {
    if (_compiler == null) {
      return _createError(ErrorKind.internal,
          'ExpressionEvaluator needs an ExpressionCompiler');
    }

    if (expression == null || expression.isEmpty) {
      return _createError(ErrorKind.invalidInput, expression);
    }

    // 1. get js scope and current JS location

    var jsFrame = _debugger.stackComputer.jsFrameForIndex(frameIndex);
    if (jsFrame == null) {
      return _createError(
          ErrorKind.internal, 'No frame with index $frameIndex');
    }

    var functionName = jsFrame.functionName;
    var jsLocation = JsLocation.fromZeroBased(jsFrame.location.scriptId,
        jsFrame.location.lineNumber, jsFrame.location.columnNumber);

    _printTrace('Expression evaluator: JS location: '
        '$functionName, $jsLocation');

    var jsScope = await _collectLocalJsScope(jsFrame);
    _printTrace('Expression evaluator: Local JS Scope: $jsScope');

    // 2. find corresponding dart location and scope

    // TODO(annagrin): handle unknown dart locations
    // Debugger does not map every js location to a dart location,
    // so this will result in expressions not evaluated in some
    // cases. Invent location matching strategy for those cases.
    // [issue 890](https://github.com/dart-lang/webdev/issues/890)
    var locationMap =
        await _locations.locationForJs(jsLocation.scriptId, jsLocation.line);

    if (locationMap == null) {
      return _createError(
          ErrorKind.internal,
          'Cannot find Dart location for JS location: '
          'function: $functionName, '
          'location: $jsLocation');
    }

    var dartLocation = locationMap.dartLocation;
    var libraryUri =
        await _modules.libraryForSource(dartLocation.uri.serverPath);

    _printTrace('Expression evaluator: dart Location: '
        '$libraryUri:${dartLocation.line}:${dartLocation.column}');

    var currentModule =
        await _modules.moduleForSource(dartLocation.uri.serverPath);
    var modules = await _modules.modules();

    _printTrace('Expression evaluator: current module: $currentModule');

    // TODO(annagrin): Handle same file names under different roots
    // [issue 891](https://github.com/dart-lang/webdev/issues/891)
    var jsModules = {'dart': 'dart_sdk', 'core': 'dart_sdk'};
    for (var serverPath in modules.keys) {
      var module = modules[serverPath];
      var library = await _modules.libraryForSource(serverPath);

      var libraryPath = library.path;
      if (library.scheme == 'package') {
        libraryPath = libraryPath.split('/').skip(1).join('/');
      }
      var name = pathToJSIdentifier(libraryPath.replaceAll('.dart', ''));
      jsModules[name] = module;
    }

    var compilationResult = await _compiler.compileExpressionToJs(
        isolateId,
        libraryUri.toString(),
        dartLocation.line,
        dartLocation.column,
        jsModules,
        jsScope,
        currentModule,
        expression);

    // 5. send js expression to chrome to evaluate

    var isError = compilationResult.isError;
    var jsExpression = compilationResult.result;

    if (isError) {
      // Frontend currently gives a text message including library name
      // and function name on compilation error. Strip this information
      // since it is shows syntetic names only used for debugger during
      // expression evaluation.
      //
      // TODO(annagrin): modify frontend to avoid stripping dummy names
      // [issue 40449](https://github.com/dart-lang/sdk/issues/40449)
      var error = jsExpression;

      if (error.startsWith('[')) {
        error = error.substring(1);
      }
      if (error.endsWith(']')) {
        error = error.substring(0, error.lastIndexOf(']'));
      }

      if (error.contains('InternalError: ')) {
        error = error.replaceAll('InternalError: ', '');
        return _createError(ErrorKind.internal, error);
      }

      error = error.replaceAll(
          RegExp('org-dartlang-debug:synthetic_debug_expression:.* Error: '),
          '');
      return _createError(ErrorKind.compilation, error);
    }

    _printTrace('Expression evaluator: jsExpression: $jsExpression');

    var result =
        await _debugger.evaluateJsOnCallFrameIndex(frameIndex, jsExpression);

    if (result.type == 'string') {
      var error = '${result.value}';
      if (error.startsWith('ReferenceError: ')) {
        error = error.replaceFirst('ReferenceError: ', '');
        return _createError(ErrorKind.reference, error);
      }
      if (error.startsWith('TypeError: ')) {
        error = error.replaceFirst('TypeError: ', '');
        return _createError(ErrorKind.type, error);
      }
    }

    _printTrace('Expression evaluator: result: $result');

    // 6. Return evaluation result or error
    return result;
  }

  String _valueToLiteral(RemoteObject value) {
    if (value.value == null) {
      return null;
    }

    var ret = value.value.toString();
    if (value.type == 'string') {
      return '\'$ret\'';
    }

    return ret;
  }

  Future<Map<String, String>> _collectLocalJsScope(WipCallFrame frame) async {
    var jsScope = <String, String>{};

    void collectVariables(
        String scopeType, Iterable<chrome.Property> variables) {
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
          // of uncaptured variables

          var capturedValue = _valueToLiteral(value);
          jsScope[name] = capturedValue ?? name;
        }
        if (scopeType == 'local') {
          jsScope[name] = name;
        }
      }
    }

    var scopeChain = filterScopes(frame).reversed;

    // skip library and main scope
    for (var scope in scopeChain) {
      var scopeProperties =
          await _debugger.getProperties(scope.object.objectId);

      collectVariables(scope.scope, scopeProperties);
    }

    return jsScope;
  }
}
