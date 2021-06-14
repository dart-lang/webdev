// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

typedef LogWriter = void Function(Level level, String message,
    {String error, String loggerName, String stackTrace});

StreamSubscription<LogRecord> _loggerSub;

/// Configure test log writer.
///
/// Tests and groups of tests can use this to configure
/// individual log writers on setup.
///
/// For example, to verbose printing during debugging:
///
/// group('shared context', () {
///     setUpAll(() async {
///       configureLogWriter(
///           customLogWriter: (level, message,
///                   {loggerName, error, stackTrace, verbose}) =>
///               print(message));
///
///       await context.setUp();
///     });
void configureLogWriter({LogWriter customLogWriter}) {
  _logWriter = customLogWriter ?? _logWriter;
  Logger.root.level = Level.ALL;
  _loggerSub?.cancel();
  _loggerSub = Logger.root.onRecord.listen((event) {
    logWriter(event.level, event.message,
        error: '${event.error}',
        loggerName: event.loggerName,
        stackTrace: '${event.stackTrace}');
  });
}

void stopLogWriter() {
  _loggerSub?.cancel();
  _loggerSub = null;
}

LogWriter _logWriter = (level, message,
        {String error, String loggerName, String stackTrace}) =>
    printOnFailure('[$level] $loggerName: $message');

LogWriter get logWriter => _logWriter;
