// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:io/ansi.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:logging/logging.dart';

var _verbose = false;

var _loggerName = RegExp(r'^(\w)+: ');

/// Sets the verbosity of the current [logHandler].
void setVerbosity(bool verbose) => _verbose = verbose;

void Function(Level, String) _logHandler =
    (level, message) => _colorLog(level, message, verbose: _verbose);

void Function(Level level, String message) get logHandler => _logHandler;

void setLogHandler(void Function(Level, String, {bool verbose}) newHandler) {
  _logHandler =
      (level, message) => newHandler(level, message, verbose: _verbose);
}

/// Colors the message and writes it to stdout.
///
/// If the [level] is not contained in the message, one will be inserted.
void _colorLog(Level level, String message, {bool verbose}) {
  verbose ??= false;
  AnsiCode color;
  if (level < Level.WARNING) {
    color = cyan;
  } else if (level < Level.SEVERE) {
    color = yellow;
  } else {
    color = red;
  }
  var multiline = message.contains('\n') && !message.endsWith('\n');
  var eraseLine = _verbose ? '' : '\x1b[2K\r';
  var colorLevel = color.wrap('[$level]');
  if (!verbose) message = trimLoggerName(message);

  stdout.write('$eraseLine$colorLevel $message');

  // Prevent multilines and severe messages from being erased.
  if (level > Level.INFO || verbose || multiline) {
    stdout.writeln('');
  }
}

/// Trims [level] from [message] if it is prefixed by it.
String trimLevel(Level level, String message) => message.startsWith('[$level]')
    ? message.replaceFirst('[$level]', '').trimLeft()
    : message;

/// Removes the logger name from the [message] if one is present.
String trimLoggerName(String message) {
  var match = _loggerName.firstMatch(message);
  // Remove the logger name.
  if (match != null) message = message.substring(match.end);
  return message;
}

/// Detects if the [ServerLog] contains a [Level] and returns the
/// resulting value.
///
/// If the [ServerLog] does not contain a [Level], null will be returned.
Level levelForLog(ServerLog serverLog) {
  var log = serverLog.log;
  Level recordLevel;
  for (var level in Level.LEVELS) {
    if (log.startsWith('[$level]')) {
      recordLevel = level;
      break;
    }
  }
  return recordLevel;
}
