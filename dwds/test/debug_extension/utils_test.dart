@TestOn('browser')
@JS()
library utils_test;

import 'dart:js_util';

import 'package:js/js.dart';
import 'package:test/test.dart';

import '../../debug_extension/web/chrome_api.dart';
import '../../debug_extension/web/utils.dart';

void main() {
  group('activeTab', () {
    setUp(() {
      // Create the chrome object and tabs property
      final chrome = newObject();
      final tabs = newObject();
      setProperty(chrome, 'tabs', tabs);
      setProperty(globalThis, 'chrome', chrome);
    });

    test('returns the active tab when found', () async {
      final chrome = getProperty(globalThis, 'chrome');
      final tabs = getProperty(chrome, 'tabs');

      // Mock chrome.tabs.query
      setProperty(
        tabs,
        'query',
        allowInterop((QueryInfo info, Function callback) {
          expect(info.active, isTrue);
          expect(info.currentWindow, isTrue);

          final tab = newObject();
          setProperty(tab, 'id', 123);
          setProperty(tab, 'url', 'http://google.com');

          callback([tab]);
        }),
      );

      final tab = await activeTab;
      expect(tab, isNotNull);
      expect(tab!.id, 123);
      expect(tab.url, 'http://google.com');
    });

    test('returns null when no active tab found', () async {
      final chrome = getProperty(globalThis, 'chrome');
      final tabs = getProperty(chrome, 'tabs');

      // Mock chrome.tabs.query to return empty list
      setProperty(
        tabs,
        'query',
        allowInterop((QueryInfo info, Function callback) {
          callback([]);
        }),
      );

      final tab = await activeTab;
      expect(tab, isNull);
    });
  });
}
