import 'package:build_daemon/data/server_log.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:webdev/src/logging.dart';

void main() {
  group('trimLoggerName', () {
    test('properly removes logger names', () {
      expect(trimLoggerName('SomeLogName: foo bar'), equals('foo bar'));
    });

    test('leaves messages untouched if no logger name is present', () {
      expect(trimLoggerName('foo bar looksLikeALoggerName: '),
          equals('foo bar looksLikeALoggerName: '));
    });

    test('works with empty messages', () {
      expect(trimLoggerName(''), equals(''));
    });

    test('assumes logger names is one word', () {
      expect(trimLoggerName('not a logger: foo bar'),
          equals('not a logger: foo bar'));
      expect(trimLoggerName('foo baz: foo bar'), equals('foo baz: foo bar'));
    });

    test('assumes loggers are directly at the front of a message', () {
      expect(
          trimLoggerName(' notLogger: foo bar'), equals(' notLogger: foo bar'));
    });
  });

  group('levelForLog', () {
    test('correctly returns the level from the log', () {
      expect(levelForLog(ServerLog((b) => b.log = '[INFO] foo bar')),
          equals(Level.INFO));
      expect(levelForLog(ServerLog((b) => b.log = '[SEVERE] foo bar')),
          equals(Level.SEVERE));
    });

    test('returns null if no level is present', () {
      expect(levelForLog(ServerLog((b) => b.log = 'foo bar')), isNull);
    });

    test('only looks for levels at the start of a log', () {
      expect(levelForLog(ServerLog((b) => b.log = 'foo bar [INFO]')), isNull);
    });
  });

  group('trimLevel', () {
    test('correctly trims the level from the message', () {
      expect(trimLevel(Level.INFO, '[INFO]foo bar'), equals('foo bar'));
      expect(trimLevel(Level.INFO, '[INFO]no space'), equals('no space'));
    });

    test('leaves the message untouched if the level is not present', () {
      expect(trimLevel(Level.INFO, '[SEVERE] foo bar'),
          equals('[SEVERE] foo bar'));
    });
  });
}
