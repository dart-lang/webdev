// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library;

// TODO: https://github.com/dart-lang/webdev/issues/2508
// ignore: deprecated_member_use
import 'package:js/js.dart';

import 'utils.dart';

enum _LogLevel { info, warn, error }

void debugLog(String msg, {String? prefix, bool verbose = false}) {
  _log(msg, prefix: prefix, verbose: verbose);
}

void debugWarn(String msg, {String? prefix, bool verbose = false}) {
  _log(msg, prefix: prefix, level: _LogLevel.warn, verbose: verbose);
}

void debugError(String msg, {String? prefix, bool verbose = false}) {
  _log(msg, prefix: prefix, level: _LogLevel.error, verbose: verbose);
}

void _log(
  String msg, {
  bool verbose = false,
  _LogLevel? level,
  String? prefix,
}) {
  if (!verbose && !isDevMode) return;
  final logMsg = prefix != null ? '[$prefix] $msg' : msg;
  final logLevel = level ?? _LogLevel.info;
  switch (logLevel) {
    case _LogLevel.error:
      _console.error(logMsg);
    case _LogLevel.warn:
      _console.warn(logMsg);
    case _LogLevel.info:
      _console.log(logMsg);
  }
}

@JS('console')
external _Console get _console;

@JS()
@anonymous
class _Console {
  external void log(
    String header, [
    String style1,
    String style2,
    String style3,
  ]);

  external void warn(
    String header, [
    String style1,
    String style2,
    String style3,
  ]);

  external void error(
    String header, [
    String style1,
    String style2,
    String style3,
  ]);
}
