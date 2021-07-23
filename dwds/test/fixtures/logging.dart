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
/// Tests and groups of tests can use this to configure individual
/// log writers on setup.
///
/// Note that the logwriter needs to be set in both `setUpAll` and
/// `setUp` to store messages for the same zone as the failure in
/// order to report all stored messages on that failure.
///
/// For example, to enable verbose printing during debugging:
///
/// void setCurrentLogWriter() {
///   // Note: change 'printOnFailure' to 'print' for debug printing.
///   configureLogWriter(
///        customLogWriter: (level, message,
///                {error, loggerName, stackTrace}) =>
///            printOnFailure('[$level] $loggerName: $message'));
///  }
///
/// group('shared context', () {
///     setUpAll(() async {
///       // Set the logger for the current group.
///       setCurrentLogWriter();
///       await context.setUp();
///     });
///
///     setUp(() async {
///       // Reset the logger for the current test.
///       setCurrentLogWriter();
///     });
///
///     ...
/// });
void configureLogWriter({LogWriter customLogWriter}) {
  _logWriter = customLogWriter ?? _logWriter;
  Logger.root.level = Level.ALL;
  _loggerSub?.cancel();
  _loggerSub = Logger.root.onRecord.listen((event) {
    logWriter(event.level, event.message,
        error: event.error?.toString(),
        loggerName: event.loggerName,
        stackTrace: event.stackTrace?.toString());
  });
}

void stopLogWriter() {
  _loggerSub?.cancel();
  _loggerSub = null;
}

LogWriter _logWriter = createLogWriter();

LogWriter createLogWriter({bool debug}) =>
    (level, message, {String error, String loggerName, String stackTrace}) {
      var printFn = debug ? print : printOnFailure;
      var errorMessage = error == null ? '' : ':\n$error';
      var stackMessage = stackTrace == null ? '' : ':\n$stackTrace';
      printFn('[$level] $loggerName: $message'
          '$errorMessage'
          '$stackMessage');
    };

LogWriter get logWriter => _logWriter;
