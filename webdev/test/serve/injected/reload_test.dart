// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';
import 'package:webdriver/io.dart';

import 'injected_fixture.dart';

void main() {
  InjectedFixture fixture;
  Process chromeDriver;

  setUpAll(() async {
    try {
      chromeDriver = await Process.start(
          'chromedriver', ['--port=4444', '--url-base=wd/hub']);
    } catch (e) {
      throw StateError(
          'Could not start ChromeDriver. Is it installed?\nError: $e');
    }
  });

  tearDownAll(() {
    chromeDriver.kill();
  });

  group('Injected client', () {
    setUp(() async {
      fixture = await InjectedFixture.create();
    });

    tearDown(() async {
      await fixture?.tearDown();
      fixture = null;
    });

    test('can hot restart changes ', () async {
      await fixture.buildAndLoad(['--auto=restart']);
      await fixture.changeInput();

      var source = await fixture.webdriver.pageSource;

      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains('Hello World!'), isTrue);
      expect(source.contains('Gary is awesome!'), isTrue);
      // The ext.flutter.disassemble callback is invoked and waited for.
      expect(source,
          contains('start disassemble end disassemble Gary is awesome'));

      await fixture.webdev.kill();
    });

    test('can hot restart while paused', () async {
      await fixture.buildAndLoad(['--debug']);

      await fixture.webdriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      var debugServiceLine = '';
      while (!debugServiceLine.contains('Debug service listening')) {
        debugServiceLine = await fixture.webdev.stdout.next;
      }
      var debugUri =
          debugServiceLine.substring(debugServiceLine.indexOf('ws://')).trim();
      var client = await vmServiceConnectUri(debugUri);
      var windows = await fixture.webdriver.windows.toList();
      await fixture.webdriver.driver.switchTo.window(windows.first);
      var vm = await client.getVM();
      var isolateId = vm.isolates.first.id;
      await client.streamListen('Debug');
      var stream = client.onEvent('Debug');
      var scriptList = await client.getScripts(isolateId);
      var main = scriptList.scripts
          .firstWhere((script) => script.uri.contains('main.dart'));
      await client.addBreakpoint(isolateId, main.id, 13);
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

      await fixture.changeInput();
      await client.streamListen('Isolate');
      stream = client.onEvent('Isolate');
      await client.callServiceExtension('hotRestart');
      await stream.firstWhere((event) => event.kind == EventKind.kIsolateStart);
      var source = await fixture.webdriver.pageSource;

      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains('Hello World!'), isTrue);
      expect(source.contains('Gary is awesome!'), isTrue);

      // Should not be paused.
      vm = await client.getVM();
      isolateId = vm.isolates.first.id;
      var isolate = await client.getIsolate(isolateId) as Isolate;
      expect(isolate.pauseEvent.kind, EventKind.kResume);
      expect(isolate.breakpoints.isEmpty, isTrue);

      await fixture.webdev.kill();
      // TODO(sdk/issues/37364) - Remove once corresponding SDK issue is fixed.
    }, skip: Platform.isWindows);

    test('can live reload changes ', () async {
      await fixture.buildAndLoad(['--auto=refresh']);
      await fixture.changeInput();

      var source = await fixture.webdriver.pageSource;

      // A full reload should clear the state.
      expect(source.contains('Hello World!'), isFalse);
      expect(source.contains('Gary is awesome!'), isTrue);

      await fixture.webdev.kill();
    });
  });
}
