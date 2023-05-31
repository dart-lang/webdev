// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class JsBuilder {
  var _indent = 0;
  final _buffer = StringBuffer();

  String? _built;
  String build() => _built ??= _buffer.toString();

  JsBuilder();

  void write(String item) {
    _buffer.write(item);
  }

  void writeLine(String item) {
    _buffer.writeln(item);
  }

  void writeAll(Iterable<String> items, [String separator = '']) {
    _buffer.writeAll(items, separator);
  }

  void _writeIndent() {
    writeAll([for (var i = 0; i < _indent * 2; i++) ' '], '');
  }

  void writeWithIndent(String item) {
    _writeIndent();
    write(item);
  }

  void writeLineWithIndent(String line) {
    _writeIndent();
    writeLine(line);
  }

  void writeMultiLineExpression(Iterable<String> lines) {
    var i = 0;
    for (var line in lines) {
      if (i == 0) {
        writeLine(line);
      } else if (i < lines.length - 1) {
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
    write('(');
    writeAll(args, ', ');
    write(')');
  }

  // try {
  //   $expression;
  // } catch (error) {
  //   error.name + ": " + error.message;
  // };
  void writeTryCatchExpression(void Function() build) {
    writeLineWithIndent('try {');

    increaseIndent();
    writeWithIndent('');
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
    writeAll(params, ', ');
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
      writeMultiLineExpression(body);
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
              writeMultiLineExpression(body);
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
  ///     }.bind(__t$this)($params);
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
                      writeMultiLineExpression(body);
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
