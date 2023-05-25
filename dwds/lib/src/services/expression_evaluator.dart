// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/dart_scope.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/conversions.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:dwds/src/utilities/objects.dart' as chrome;
import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class EvaluationErrorKind {
  EvaluationErrorKind._();

  static const compilation = 'CompilationError';
  static const type = 'TypeError';
  static const reference = 'ReferenceError';
  static const internal = 'InternalError';
  static const asyncFrame = 'AsyncFrameError';
  static const invalidInput = 'InvalidInputError';
  static const loadModule = 'LoadModuleError';
}

/// ExpressionEvaluator provides functionality to evaluate dart expressions
/// from text user input in the debugger, using chrome remote debugger to
/// collect context for evaluation (scope, types, modules), and using
/// ExpressionCompilerInterface to compile dart expressions to JavaScript.
class ExpressionEvaluator {
  final String _entrypoint;
  final AppInspectorInterface _inspector;
  final Debugger _debugger;
  final Locations _locations;
  final Modules _modules;
  final ExpressionCompiler _compiler;
  final _logger = Logger('ExpressionEvaluator');
  bool _closed = false;

  /// Strip synthetic library name from compiler error messages.
  static final _syntheticNameFilterRegex =
      RegExp('org-dartlang-debug:synthetic_debug_expression:.*:.*Error: ');

  /// Find module path from the XHR call network error message received from chrome.
  ///
  /// Example:
  /// NetworkError: Failed to load 'http://<hostname>.com/path/to/module.js?<cache_busting_token>'
  static final _loadModuleErrorRegex =
      RegExp(r".*Failed to load '.*\.com/(.*\.js).*");

  ExpressionEvaluator(
    this._entrypoint,
    this._inspector,
    this._debugger,
    this._locations,
    this._modules,
    this._compiler,
  );

  /// Create and error with [severity] and [message]
  ///
  /// [severity] is one of kinds in [EvaluationErrorKind]
  RemoteObject createError(String severity, String message) {
    return RemoteObject(
      <String, String>{'type': severity, 'value': message},
    );
  }

  void close() {
    _closed = true;
  }

  /// Evaluate dart expression inside a given library.
  ///
  /// Uses ExpressionCompiler interface to compile the expression to
  /// JavaScript and sends evaluate requests to chrome to calculate
  /// the final result.
  ///
  /// Returns remote object containing the result of evaluation or error.
  ///
  /// [isolateId] current isolate ID.
  /// [libraryUri] dart library to evaluate the expression in.
  /// [expression] dart expression to evaluate.
  Future<RemoteObject> evaluateExpression(
    String isolateId,
    String? libraryUri,
    String expression,
    Map<String, String>? scope,
  ) async {
    if (_closed) {
      return createError(
        EvaluationErrorKind.internal,
        'expression evaluator closed.',
      );
    }

    scope ??= {};

    if (expression.isEmpty) {
      return createError(
        EvaluationErrorKind.invalidInput,
        expression,
      );
    }

    if (libraryUri == null) {
      return createError(
        EvaluationErrorKind.invalidInput,
        'no library uri',
      );
    }

    final module = await _modules.moduleForLibrary(libraryUri);
    if (module == null) {
      return createError(
        EvaluationErrorKind.internal,
        'no module for $libraryUri',
      );
    }

    // Wrap the expression in a lambda so we can call it as a function.
    expression = _createDartLambda(expression, scope.keys);
    _logger.finest('Evaluating "$expression" at $module');

    // Compile expression using an expression compiler, such as
    // frontend server or expression compiler worker.
    final compilationResult = await _compiler.compileExpressionToJs(
      isolateId,
      libraryUri.toString(),
      0,
      0,
      {},
      {},
      module,
      expression,
    );

    final isError = compilationResult.isError;
    final jsResult = compilationResult.result;
    if (isError) {
      return _formatCompilationError(jsResult);
    }

    // Strip try/catch incorrectly added by the expression compiler.
    var jsCode = _maybeStripTryCatch(jsResult);

    // Send JS expression to chrome to evaluate.
    jsCode = _createEvalFunction(jsCode, scope.keys);

    _logger.finest('Evaluating JS: "$jsCode" with scope: $scope');
    var result = await _inspector.callFunction(jsCode, scope.values);
    result = await _formatEvaluationError(result);

    _logger.finest('Evaluated "$expression" to "${result.json}"');
    return result;
  }

  /// Evaluate dart expression inside a given frame (function).
  ///
  /// Gets necessary context (types, scope, module names) data from chrome,
  /// uses ExpressionCompiler interface to compile the expression to
  /// JavaScript, and sends evaluate requests to chrome to calculate the
  /// final result.
  ///
  /// Returns remote object containing the result of evaluation or error.
  ///
  /// [isolateId] current isolate ID.
  /// [frameIndex] JavaScript frame to evaluate the expression in.
  /// [expression] dart expression to evaluate.
  Future<RemoteObject> evaluateExpressionInFrame(
    String isolateId,
    int frameIndex,
    String expression,
    Map<String, String>? scope,
  ) async {
    scope ??= {};

    if (expression.isEmpty) {
      return createError(EvaluationErrorKind.invalidInput, expression);
    }

    // Get JS scope and current JS location.
    final jsFrame = _debugger.jsFrameForIndex(frameIndex);
    if (jsFrame == null) {
      return createError(
          EvaluationErrorKind.asyncFrame,
          'Expression evaluation in async frames '
          'is not supported. No frame with index $frameIndex.');
    }

    final functionName = jsFrame.functionName;
    final jsLine = jsFrame.location.lineNumber;
    final jsScriptId = jsFrame.location.scriptId;
    final jsColumn = jsFrame.location.columnNumber;
    final jsScope = await _collectLocalJsScope(jsFrame);

    // Find corresponding dart location and scope.
    final url = _debugger.urlForScriptId(jsScriptId);
    if (url == null) {
      return createError(
        EvaluationErrorKind.internal,
        'Cannot find url for JS script: $jsScriptId',
      );
    }
    final locationMap = await _locations.locationForJs(url, jsLine, jsColumn);
    if (locationMap == null) {
      return createError(
          EvaluationErrorKind.internal,
          'Cannot find Dart location for JS location: '
          'url: $url, '
          'function: $functionName, '
          'line: $jsLine, '
          'column: $jsColumn');
    }

    final dartLocation = locationMap.dartLocation;
    final dartSourcePath = dartLocation.uri.serverPath;
    final libraryUri = await _modules.libraryForSource(dartSourcePath);
    if (libraryUri == null) {
      return createError(
        EvaluationErrorKind.internal,
        'no libraryUri for $dartSourcePath',
      );
    }

    final module = await _modules.moduleForLibrary(libraryUri.toString());
    if (module == null) {
      return createError(
        EvaluationErrorKind.internal,
        'no module for $libraryUri ($dartSourcePath)',
      );
    }

    _logger.finest('Evaluating "$expression" at $module, '
        '$libraryUri:${dartLocation.line}:${dartLocation.column} '
        'with scope: $scope');

    if (scope.isNotEmpty) {
      scope = await _collectTotalDartScope(frameIndex, scope, jsScope);
      expression = _createDartLambda(expression, scope.keys);
    }

    _logger.finest('Compiling "$expression"');

    // Compile expression using an expression compiler, such as
    // frontend server or expression compiler worker.
    //
    // TODO(annagrin): map JS locals to dart locals in the expression
    // and JS scope before passing them to the dart expression compiler.
    // Issue:  https://github.com/dart-lang/sdk/issues/40273
    final compilationResult = await _compiler.compileExpressionToJs(
      isolateId,
      libraryUri.toString(),
      dartLocation.line,
      dartLocation.column,
      {},
      jsScope,
      module,
      expression,
    );

    final isError = compilationResult.isError;
    final jsResult = compilationResult.result;
    if (isError) {
      return _formatCompilationError(jsResult);
    }

    // Strip try/catch incorrectly added by the expression compiler.
    var jsCode = _maybeStripTryCatch(jsResult);

    late RemoteObject result;
    if (scope.isNotEmpty) {
      final totalJsScope = await _collectTotalJsScope(frameIndex, scope);

      // Send JS expression to chrome to evaluate.
      jsCode = _createEvalFunction(jsCode, totalJsScope.keys);

      _logger.finest('Evaluating JS: "$jsCode" with scope: $totalJsScope');
      result = await _inspector.callFunction(jsCode, totalJsScope.values);
    } else {
      // Send JS expression to chrome to evaluate.
      jsCode = _createEvalExpression(jsCode);

      // Send JS expression to chrome to evaluate.
      _logger.finest('Evaluating JS: "$jsCode"');
      result = await _debugger.evaluateJsOnCallFrameIndex(frameIndex, jsCode);
    }

    result = await _formatEvaluationError(result);
    _logger.finest('Evaluated "$expression" to "${result.json}"');
    return result;
  }

  String? _getObjectId(RemoteObject? object) =>
      object?.objectId ?? dartIdFor(object?.value);

  Future<Map<String, String>> _collectTotalDartScope(
    int frame,
    Map<String, String> dartScope,
    Map<String, String> jsScope,
  ) async {
    // Evaluate list of variables in a batch.
    final variables = jsScope.keys.join(', ');
    final expression = '[$variables]';
    final list = await _debugger.evaluateJsOnCallFrameIndex(frame, expression);

    if (list.objectId != null) {
      final elements = await _inspector.getProperties(list.objectId!);
      final values = elements.where((e) => e.name != 'length');

      final objects = Map.fromIterables(jsScope.keys, values);
      for (var e in objects.entries) {
        final objectId = _getObjectId(e.value.value);
        if (objectId != null) {
          dartScope[e.key] = objectId;
        }
      }
    }
    return dartScope;
  }

  Future<Map<String, String>> _collectTotalJsScope(
    int frame,
    Map<String, String> dartScope,
  ) async {
    final thisObject =
        await _debugger.evaluateJsOnCallFrameIndex(frame, 'this');
    final thisObjectId = thisObject.objectId;

    final totalJsScope = Map<String, String>.from(dartScope);
    if (thisObjectId != null) {
      totalJsScope['this'] = thisObjectId;
    }
    return totalJsScope;
  }

  RemoteObject _formatCompilationError(String error) {
    // Frontend currently gives a text message including library name
    // and function name on compilation error. Strip this information
    // since it shows synthetic names that are only used for temporary
    // debug library during expression evaluation.
    //
    // TODO(annagrin): modify frontend to avoid stripping dummy names
    // [issue 40449](https://github.com/dart-lang/sdk/issues/40449)
    if (error.startsWith('[')) {
      error = error.substring(1);
    }
    if (error.endsWith(']')) {
      error = error.substring(0, error.lastIndexOf(']'));
    }
    if (error.contains('InternalError: ')) {
      error = error.replaceAll('InternalError: ', '');
      return createError(EvaluationErrorKind.internal, error);
    }
    error = error.replaceAll(_syntheticNameFilterRegex, '');
    return createError(EvaluationErrorKind.compilation, error);
  }

  Future<RemoteObject> _formatEvaluationError(RemoteObject result) async {
    if (result.type == 'string') {
      var error = '${result.value}';
      if (error.startsWith('ReferenceError: ')) {
        error = error.replaceFirst('ReferenceError: ', '');
        return createError(EvaluationErrorKind.reference, error);
      } else if (error.startsWith('TypeError: ')) {
        error = error.replaceFirst('TypeError: ', '');
        return createError(EvaluationErrorKind.type, error);
      } else if (error.startsWith('NetworkError: ')) {
        var modulePath = _loadModuleErrorRegex.firstMatch(error)?.group(1);
        final module = modulePath != null
            ? await globalLoadStrategy.moduleForServerPath(
                _entrypoint,
                modulePath,
              )
            : 'unknown';
        modulePath ??= 'unknown';
        error = 'Module is not loaded : $module (path: $modulePath). '
            'Accessing libraries that have not yet been used in the '
            'application is not supported during expression evaluation.';
        return createError(EvaluationErrorKind.loadModule, error);
      }
    }
    return result;
  }

  Future<Map<String, String>> _collectLocalJsScope(WipCallFrame frame) async {
    final jsScope = <String, String>{};

    void collectVariables(
      Iterable<chrome.Property> variables,
    ) {
      for (var p in variables) {
        final name = p.name;
        final value = p.value;
        // TODO: null values represent variables optimized by v8.
        // Show that to the user.
        if (name != null && value != null && !_isUndefined(value)) {
          jsScope[name] = name;
        }
      }
    }

    // skip library and main scope
    final scopeChain = filterScopes(frame).reversed;
    for (var scope in scopeChain) {
      final objectId = scope.object.objectId;
      if (objectId != null) {
        final scopeProperties = await _inspector.getProperties(objectId);
        collectVariables(scopeProperties);
      }
    }

    return jsScope;
  }

  bool _isUndefined(RemoteObject value) => value.type == 'undefined';

  static String _createDartLambda(
    String expression,
    Iterable<String> params,
  ) =>
      '(${params.join(', ')}) { return $expression; }';

  /// Strip try/catch incorrectly added by the expression compiler.
  /// TODO: remove adding try/catch block in expression compiler.
  /// https://github.com/dart-lang/webdev/issues/1341, then remove
  /// this stripping code.
  static String _maybeStripTryCatch(String jsCode) {
    // Match the wrapping generated by the expression compiler exactly
    // so the matching does not succeed naturally after the wrapping is
    // removed:
    //
    // Expression compiler's wrapping:
    //
    // '\ntry {'
    // '\n  ($jsExpression('
    // '\n    $args'
    // '\n  ))'
    // '\n} catch (error) {'
    // '\n  error.name + ": " + error.message;'
    // '\n}';
    //
    final lines = jsCode.split('\n');
    if (lines.length > 5) {
      final tryLines = lines.getRange(0, 2).toList();
      final bodyLines = lines.getRange(2, lines.length - 3);
      final catchLines =
          lines.getRange(lines.length - 3, lines.length).toList();
      if (tryLines[0].isEmpty &&
          tryLines[1] == 'try {' &&
          catchLines[0] == '} catch (error) {' &&
          catchLines[1] == '  error.name + ": " + error.message;' &&
          catchLines[2] == '}') {
        return bodyLines.join('\n');
      }
    }
    return jsCode;
  }

  /// Create JS expression to pass to `Debugger.evaluateOnCallFrame`.
  static String _createEvalExpression(String expression) {
    final body = expression.split('\n').where((e) => e.isNotEmpty);

    final builder = JsBuilder();
    builder.createEvalExpression(body);
    return builder.build();
  }

  /// Create JS function  to invoke in `Runtime.callFunctionOn`.
  static String _createEvalFunction(
    String function,
    Iterable<String> params,
  ) {
    final body = function.split('\n').where((e) => e.isNotEmpty);

    final builder = JsBuilder();
    if (params.contains('this')) {
      builder.writeEvalBoundFunction(body, params);
    } else {
      builder.writeEvalStaticFunction(body, params);
    }
    return builder.build();
  }
}

class JsBuilder {
  var _indent = 0;
  final _buffer = StringBuffer();

  String? _built;
  String build() => _built ??= _buffer.toString();

  JsBuilder();

  void _writeIndent() {
    _buffer.writeAll([for (var i = 0; i < _indent * 2; i++) ' ']);
  }

  void write(String item) {
    _buffer.write(item);
  }

  void writeLine(String item) {
    _buffer.writeln(item);
  }

  void writeAll(Iterable<String> items, [String separator = ', ']) {
    _buffer.writeAll(items, separator);
  }

  void writeWithIndent(String item) {
    _writeIndent();
    _buffer.write(item);
  }

  void writeLineWithIndent(String line) {
    _writeIndent();
    _buffer.writeln(line);
  }

  void writeAllLinesWithIndent(Iterable<String> lines) {
    var i = 0;
    for (var line in lines) {
      if (i < lines.length - 1) {
        writeLineWithIndent(line);
      } else {
        writeWithIndent(line);
      }
      i++;
    }
  }

  void increaseIndent() {
    _indent++;
  }

  void decreaseIndent() {
    if (_indent != 0) _indent--;
  }

  /// $function($args);
  void writeCallExpression(
    Iterable<String> args,
    void Function() build,
  ) {
    build();
    _buffer.write('(');
    _buffer.writeAll(args, ', ');
    _buffer.write(')');
  }

  // try {
  //   $expression;
  // } catch (error) {
  //   error.name + ": " + error.message;
  // };
  void writeTryCatchExpression(void Function() build) {
    writeLineWithIndent('try {');

    increaseIndent();
    build();
    writeLine('');
    decreaseIndent();

    writeLineWithIndent('} catch (error) {');
    writeLineWithIndent('  error.name + ": " + error.message;');
    writeWithIndent('}');
  }

  // try {
  //   $statement
  // } catch (error) {
  //   return error.name + ": " + error.message;
  // };
  void writeTryCatchStatement(void Function() build) {
    writeLineWithIndent('try {');

    increaseIndent();
    build();
    writeLine('');
    decreaseIndent();

    writeLineWithIndent('} catch (error) {');
    writeLineWithIndent('  return error.name + ": " + error.message;');
    writeWithIndent('}');
  }

  /// return $expression;
  void writeReturnStatement(void Function() build) {
    writeWithIndent('return ');
    build();
    write(';');
  }

  /// function($args) {
  ///   $body
  /// };
  void writeFunctionDefinition(
    Iterable<String> params,
    void Function() build,
  ) {
    write('function (');
    writeAll(params);
    writeLine(') {');

    increaseIndent();
    build();
    writeLine('');
    decreaseIndent();

    writeWithIndent('}');
  }

  /// $function.bind($to)
  void writeBindExpression(
    String to,
    void Function() build,
  ) {
    build();
    write('.bind(');
    write(to);
    write(')');
  }

  /// try {
  ///   $expression;
  /// } catch (error) {
  ///   error.name + ": " + error.message;
  /// }
  void createEvalExpression(Iterable<String> body) {
    writeTryCatchExpression(() {
      writeAllLinesWithIndent(body);
      write(';');
    });
  }

  /// function ($params) {
  ///   try {
  ///     return $function($params);
  ///   } catch (error) {
  ///     return error.name + ": " + error.message;
  ///   }
  /// }
  void writeEvalStaticFunction(
    Iterable<String> body,
    Iterable<String> params,
  ) {
    writeFunctionDefinition(
      params,
      () => writeTryCatchStatement(
        () => writeReturnStatement(
          () => writeCallExpression(
            params,
            () {
              writeAllLinesWithIndent(body);
            },
          ),
        ),
      ),
    );
  }

  /// function ($params, __t$this) {
  ///   try {
  ///     return function ($params) {
  ///       return $function($params);
  ///     }.bind(__t$this)($params)
  ///   } catch (error) {
  ///     return error.name + ": " + error.message;
  ///   }
  /// }
  void writeEvalBoundFunction(
    Iterable<String> body,
    Iterable<String> params,
  ) {
    final original = 'this';
    final substitute = '__t\$this';

    final args = params.where((e) => e != original);
    final substitutedParams = [
      ...params.where((e) => e != original),
      substitute
    ];

    writeFunctionDefinition(
      substitutedParams,
      () => writeTryCatchStatement(
        () => writeReturnStatement(
          () => writeCallExpression(
            args,
            () => writeBindExpression(
              substitute,
              () => writeFunctionDefinition(
                args,
                () => writeReturnStatement(
                  () => writeCallExpression(
                    args,
                    () {
                      writeAllLinesWithIndent(body);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
