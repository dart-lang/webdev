// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/server_log.dart';
import 'package:io/ansi.dart';
import 'package:logging/logging.dart';

/// Whether this computer supports binding to IPv6 addresses.
var _maySupportIPv6 = true;

/// Returns a port that is probably, but not definitely, not in use.
///
/// This has a built-in race condition: another process may bind this port at
/// any time after this call has returned.
Future<int> findUnusedPort() async {
  int port;
  if (_maySupportIPv6) {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0,
          v6Only: true);
      port = socket.port;
      await socket.close();
    } on SocketException {
      _maySupportIPv6 = false;
    }
  }
  if (!_maySupportIPv6) {
    final socket = await RawServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    await socket.close();
  }
  return port;
}

/// Colors and writes daemon [ServerLog]s
void writeServerLog(ServerLog serverLog, bool verbose) {
  var recordLevel = _levelForLog(serverLog);
  if (recordLevel == null) {
    stdout.writeln(serverLog.log);
  } else {
    AnsiCode color;
    if (recordLevel < Level.WARNING) {
      color = cyan;
    } else if (recordLevel < Level.SEVERE) {
      color = yellow;
    } else {
      color = red;
    }
    var message = serverLog.log.replaceFirst('[$recordLevel]', '');
    var multiline = message.contains('\n');
    var eraseLine = verbose ? '' : '\x1b[2K\r';
    var level = color.wrap('[$recordLevel]');

    stdout.write('$eraseLine$level$message');
    // Prevent multilines and severe messages from being erased.
    if (recordLevel > Level.INFO || verbose || multiline) {
      stdout.writeln('');
    }
  }
}

/// Detects if the [ServerLog] contains a [Level] and returns the
/// resulting value.
///
/// If the [ServerLog] does not contain a [Level], null will be returned.
Level _levelForLog(ServerLog serverLog) {
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
