// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library logger;

import 'dart:js_util';

import 'package:js/js.dart';

import 'web_api.dart';
import 'chrome_api.dart';

bool? _isDevMode;

bool isDevMode() {
  if (_isDevMode != null) {
    return _isDevMode!;
  }

  final extensionManifest = chrome.runtime.getManifest();
  final extensionName = getProperty(extensionManifest, 'name') ?? '';
  return extensionName.contains('DEV');
}

enum _LogLevel {
  info,
  warn,
  error,
}

debugLog(
  String msg, {
  String? prefix,
  bool devOnly = true,
}) {
  _log(msg, prefix: prefix);
}

debugWarn(
  String msg, {
  String? prefix,
  bool devOnly = true,
}) {
  _log(msg, prefix: prefix, level: _LogLevel.warn);
}

debugError(
  String msg, {
  String? prefix,
  bool devOnly = true,
}) {
  _log(msg, prefix: prefix, level: _LogLevel.error);
}

void _log(
  String msg, {
  bool devOnly = true,
  _LogLevel? level,
  String? prefix,
}) {
  console.log('IS DEV MODE? ${isDevMode()}');
  if (devOnly && !isDevMode()) return;
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
