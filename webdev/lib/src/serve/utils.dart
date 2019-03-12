// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/server_log.dart';
import 'package:io/ansi.dart';
import 'package:logging/logging.dart';

/// Returns a port that is probably, but not definitely, not in use.
///
/// This has a built-in race condition: another process may bind this port at
/// any time after this call has returned.
Future<int> findUnusedPort() async {
  int port;
  ServerSocket socket;
  try {
    socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv6, 0, v6Only: true);
  } on SocketException {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  }
  port = socket.port;
  await socket.close();
  return port;
}

/// Colors the message and writes it to stdout.
///
/// If the [level] is not contained in the message, one will be inserted.
void colorLog(Level level, String message, {bool verbose}) {
  verbose ??= false;
  AnsiCode color;
  if (level < Level.WARNING) {
    color = cyan;
  } else if (level < Level.SEVERE) {
    color = yellow;
  } else {
    color = red;
  }
  var multiline = message.contains('\n');
  var eraseLine = verbose ? '' : '\x1b[2K\r';
  var colorLevel = color.wrap('[$level]');

  stdout.write('$eraseLine$colorLevel $message');
  // Prevent multilines and severe messages from being erased.
  if (level > Level.INFO || verbose || multiline) {
    stdout.writeln('');
  }
}

String trimLevel(Level level, String message) => message.startsWith('[$level]')
    ? message.replaceFirst('[$level]', '').trimLeft()
    : message;

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
