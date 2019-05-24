// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:io/ansi.dart';
import 'package:logging/logging.dart';

typedef LogWriter = void Function(Level level, String message,
    {String error, String loggerName, String stackTrace});

var _verbose = false;

/// Sets the verbosity of the current [logHandler].
void setVerbosity(bool verbose) => _verbose = verbose;

LogWriter _logWriter =
    (level, message, {String error, String loggerName, String stackTrace}) {
  // Erases the previous line
  if (!_verbose) stdout.write('\x1b[2K\r');
  var log = formatLog(level, message,
      error: error,
      loggerName: loggerName,
      stackTrace: stackTrace,
      verbose: _verbose,
      withColors: true);
  stdout.write(log);
  // Prevent multiline logs and > info messages from being erased.
  if (level > Level.INFO ||
      _verbose ||
      (log.contains('\n') && !log.endsWith('\n'))) {
    stdout.writeln('');
  }
};

LogWriter get logWriter => _logWriter;

void setLogWriter(
    void Function(Level, String,
            {String error, String loggerName, String stackTrace, bool verbose})
        newWriter) {
  _logWriter = (level, message,
          {String error, String loggerName, String stackTrace}) =>
      newWriter(level, message,
          error: error,
          loggerName: loggerName,
          stackTrace: stackTrace,
          verbose: _verbose);
}

/// Colors the message and writes it to stdout.
String formatLog(Level level, String message,
    {bool withColors,
    String error,
    String loggerName,
    String stackTrace,
    bool verbose}) {
  verbose ??= false;
  withColors ??= false;
  var buffer = StringBuffer(message);
  if (error != null) {
    buffer.writeln(error);
  }

  if (verbose && stackTrace != null) {
    buffer.writeln(stackTrace);
  }

  var formattedLevel = '[$level]';
  if (withColors) {
    AnsiCode color;
    if (level < Level.WARNING) {
      color = cyan;
    } else if (level < Level.SEVERE) {
      color = yellow;
    } else {
      color = red;
    }
    formattedLevel = color.wrap(formattedLevel);
  }

  var loggerNameOutput =
      (loggerName != null && (verbose || loggerName.contains(' ')))
          ? '$loggerName:'
          : '';
  return '$formattedLevel$loggerNameOutput $buffer';
}
