// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:io/ansi.dart';
import 'package:logging/logging.dart';

typedef LogWriter = void Function(Level level, String message,
    {String error, String loggerName, String stackTrace});

var _verbose = false;

void configureLogWriter(bool verbose, {LogWriter customLogWriter}) {
  _verbose = verbose;
  _logWriter = customLogWriter ?? _logWriter;
  Logger.root.onRecord.listen((event) {
    logWriter(event.level, event.message,
        error: '${event.error}',
        loggerName: event.loggerName,
        stackTrace: '${event.stackTrace}');
  });
}

LogWriter _logWriter =
    (level, message, {String error, String loggerName, String stackTrace}) {
  // Erases the previous line
  if (!_verbose) stdout.write('\x1b[2K\r');
  var log = formatLog(level, message,
      error: error,
      loggerName: loggerName,
      stackTrace: stackTrace,
      withColors: true);

  if (level >= Level.INFO || _verbose) {
    stdout.write(log);
    // Prevent multiline logs and > info messages from being erased.
    if (level > Level.INFO ||
        _verbose ||
        (log.contains('\n') && !log.endsWith('\n'))) {
      stdout.writeln('');
    }
  }
};

LogWriter get logWriter => _logWriter;

/// Colors the message and writes it to stdout.
String formatLog(Level level, String message,
    {bool withColors, String error, String loggerName, String stackTrace}) {
  withColors ??= false;
  var buffer = StringBuffer(message);
  if (error != null) {
    buffer.writeln(error);
  }

  if (_verbose && stackTrace != null) {
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
      (loggerName != null && (_verbose || loggerName.contains(' ')))
          ? '$loggerName:'
          : '';
  return '$formattedLevel$loggerNameOutput $buffer';
}
