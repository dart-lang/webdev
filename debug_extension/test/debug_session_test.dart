// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('browser')
@JS()
library;

import 'dart:convert';
// TODO: https://github.com/dart-lang/webdev/issues/2508
// ignore: deprecated_member_use
import 'dart:js_util';

import 'package:dwds/data/debug_info.dart';
// TODO: https://github.com/dart-lang/webdev/issues/2508
// ignore: deprecated_member_use
import 'package:js/js.dart';
import 'package:test/test.dart';

import '../web/debug_session.dart';

void main() {
  group('registerDebugEventListeners', () {
    late int onEventCount;
    late int onDetachCount;
    late int onTabRemovedCount;
    late int attachCount;

    setUp(() {
      onEventCount = 0;
      onDetachCount = 0;
      onTabRemovedCount = 0;
      attachCount = 0;

      final chrome = newObject();

      // Mock chrome.runtime.getManifest
      final runtime = newObject();
      setProperty(
        runtime,
        'getManifest',
        allowInterop(() {
          final manifest = newObject();
          setProperty(manifest, 'name', 'Dart Debug Extension');
          setProperty(manifest, 'manifest_version', 3);
          return manifest;
        }),
      );
      setProperty(chrome, 'runtime', runtime);

      // Mock chrome.storage.session.get
      final storageData = <String, String>{
        '1-debugInfo': jsonEncode(
          DebugInfo(appId: 'app-1', appInstanceId: 'inst-1'),
        ),
        '1-isAuthenticated': 'true',
        '2-debugInfo': jsonEncode(
          DebugInfo(appId: 'app-2', appInstanceId: 'inst-2'),
        ),
        '2-isAuthenticated': 'true',
      };
      final sessionStorage = newObject();
      setProperty(
        sessionStorage,
        'get',
        allowInterop((List<dynamic>? keys, Function callback) {
          final result = newObject();
          if (keys != null) {
            for (final key in keys) {
              final value = storageData[key as String];
              if (value != null) {
                setProperty(result, key, value);
              }
            }
          }
          callback(result);
        }),
      );
      final storage = newObject();
      setProperty(storage, 'session', sessionStorage);
      setProperty(storage, 'local', sessionStorage);
      setProperty(chrome, 'storage', storage);

      // Mock chrome.debugger
      final onEvent = newObject();
      setProperty(
        onEvent,
        'addListener',
        allowInterop((Function _) => onEventCount++),
      );
      final onDetach = newObject();
      setProperty(
        onDetach,
        'addListener',
        allowInterop((Function _) => onDetachCount++),
      );
      final debugger = newObject();
      setProperty(debugger, 'onEvent', onEvent);
      setProperty(debugger, 'onDetach', onDetach);
      setProperty(
        debugger,
        'attach',
        allowInterop((Object target, String version, Function? callback) {
          attachCount++;
        }),
      );
      setProperty(chrome, 'debugger', debugger);

      // Mock chrome.tabs.onRemoved
      final onRemoved = newObject();
      setProperty(
        onRemoved,
        'addListener',
        allowInterop((Function _) => onTabRemovedCount++),
      );
      final tabs = newObject();
      setProperty(tabs, 'onRemoved', onRemoved);
      setProperty(chrome, 'tabs', tabs);

      setProperty(globalThis, 'chrome', chrome);
    });

    test('registers debugger and tab listeners only once across multiple '
        'attachDebugger and registerDebugEventListeners calls', () async {
      await attachDebugger(1, trigger: Trigger.extensionIcon);
      await attachDebugger(2, trigger: Trigger.extensionIcon);
      registerDebugEventListeners();
      registerDebugEventListeners();

      expect(attachCount, 2);
      expect(onEventCount, 1);
      expect(onDetachCount, 1);
      expect(onTabRemovedCount, 1);
    });
  });
}
