import 'dart:async';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

typedef LogWriter = void Function(Level level, String message,
    {String error, String loggerName, String stackTrace});

StreamSubscription<LogRecord> _loggerSub;

void configureLogWriter({LogWriter customLogWriter}) {
  _logWriter = customLogWriter ?? _logWriter;
  Logger.root.level = Level.ALL;
  _loggerSub ??= Logger.root.onRecord.listen((event) {
    logWriter(event.level, event.message,
        error: '${event.error}',
        loggerName: event.loggerName,
        stackTrace: '${event.stackTrace}');
  });
}

void stopLogWriter() {
  _loggerSub.cancel();
  _loggerSub = null;
}

LogWriter _logWriter = (level, message,
        {String error, String loggerName, String stackTrace}) =>
    printOnFailure(message);

LogWriter get logWriter => _logWriter;
