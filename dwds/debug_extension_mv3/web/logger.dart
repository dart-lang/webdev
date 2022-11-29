// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library logger;

import 'package:js/js.dart';

import 'web_api.dart';

// Switch to true for debug logging.
bool _enableDebugLogging = true;

enum _LogLevel {
  info,
  warn,
  error,
}

debugLog(String msg, {String? prefix}) {
  _log(msg, prefix: prefix);
}

debugWarn(String msg, {String? prefix}) {
  _log(msg, prefix: prefix, level: _LogLevel.warn);
}

debugError(String msg, {String? prefix}) {
  _log(msg, prefix: prefix, level: _LogLevel.error);
}

void _log(String msg, {_LogLevel? level, String? prefix}) {
  if (!_enableDebugLogging) return;
  final logMsg = prefix != null ? '[$prefix] $msg' : msg;
  final logLevel = level ?? _LogLevel.info;
  switch (logLevel) {
    case _LogLevel.error:
      console.error(logMsg);
      break;
    case _LogLevel.warn:
      console.warn(logMsg);
      break;
    case _LogLevel.info:
      console.log(logMsg);
  }
}
