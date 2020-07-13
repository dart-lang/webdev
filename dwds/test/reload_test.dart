// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 5))

import 'package:dwds/dwds.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';

final context = TestContext(
  path: 'append_body/index.html',
);

void main() {
  group('Injected client with live reload', () {
    group('and with debugging', () {
      setUp(() async {
        await context.setUp(
            reloadConfiguration: ReloadConfiguration.liveReload);
      });

      tearDown(() async {
        await context.tearDown();
      });

      test('can live reload changes ', () async {
        await context.changeInput();

        var source = await context.webDriver.pageSource;

        // A full reload should clear the state.
        expect(source.contains('Hello World!'), isFalse);
        expect(source.contains('Gary is awesome!'), isTrue);
      });
    });

    group('and without debugging', () {
      setUp(() async {
        await context.setUp(
            reloadConfiguration: ReloadConfiguration.liveReload,
            enableDebugging: false);
      });

      tearDown(() async {
        await context.tearDown();
      });

      test('can live reload changes ', () async {
        await context.changeInput();

        var source = await context.webDriver.pageSource;

        // A full reload should clear the state.
        expect(source.contains('Hello World!'), isFalse);
        expect(source.contains('Gary is awesome!'), isTrue);
      });
    });
  });

  group('Injected client', () {
    setUp(() async {
      await context.setUp();
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('destroys and recreates the isolate during a hot restart', () async {
      var client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await context.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            _hasKind(EventKind.kIsolateExit),
            _hasKind(EventKind.kIsolateStart),
            _hasKind(EventKind.kIsolateRunnable),
          ])));

      expect(await client.callServiceExtension('hotRestart'),
          const TypeMatcher<Success>());

      await eventsDone;
    });

    test('destroys and recreates the isolate during a page refresh', () async {
      var client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await context.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            _hasKind(EventKind.kIsolateExit),
            _hasKind(EventKind.kIsolateStart),
            _hasKind(EventKind.kIsolateRunnable),
          ])));

      await context.webDriver.driver.refresh();

      await eventsDone;
    });

    test('can hot restart via the service extension', () async {
      var client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await context.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            _hasKind(EventKind.kIsolateExit),
            _hasKind(EventKind.kIsolateStart),
            _hasKind(EventKind.kIsolateRunnable),
          ])));

      expect(await client.callServiceExtension('hotRestart'),
          const TypeMatcher<Success>());

      await eventsDone;

      var source = await context.webDriver.pageSource;
      // Main is re-invoked which shouldn't clear the state.
      expect(source, contains('Hello World!'));
      expect(source, contains('Gary is awesome!'));
    });

    test('can refresh the page via the fullReload service extension', () async {
      var client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await context.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            _hasKind(EventKind.kIsolateExit),
            _hasKind(EventKind.kIsolateStart),
            _hasKind(EventKind.kIsolateRunnable),
          ])));

      expect(await client.callServiceExtension('fullReload'), isA<Success>());

      await eventsDone;

      var source = await context.webDriver.pageSource;
      // Should see only the new text
      expect(source, isNot(contains('Hello World!')));
      expect(source, contains('Gary is awesome!'));
    });

    test('can hot restart while paused', () async {
      var client = context.debugConnection.vmService;
      var vm = await client.getVM();
      var isolateId = vm.isolates.first.id;
      await client.streamListen('Debug');
      var stream = client.onEvent('Debug');
      var scriptList = await client.getScripts(isolateId);
      var main = scriptList.scripts
          .firstWhere((script) => script.uri.contains('main.dart'));
      var bpLine =
          await context.findBreakpointLine('printCount', isolateId, main);
      await client.addBreakpoint(isolateId, main.id, bpLine);
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

      await context.changeInput();
      await client.callServiceExtension('hotRestart');
      var source = await context.webDriver.pageSource;

      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains('Hello World!'), isTrue);
      expect(source.contains('Gary is awesome!'), isTrue);

      // Should not be paused.
      vm = await client.getVM();
      isolateId = vm.isolates.first.id;
      var isolate = await client.getIsolate(isolateId);
      expect(isolate.pauseEvent.kind, EventKind.kResume);
      expect(isolate.breakpoints.isEmpty, isTrue);
    });
  });

  group('Injected client with hot restart', () {
    group('and with debugging', () {
      setUp(() async {
        await context.setUp(
            reloadConfiguration: ReloadConfiguration.hotRestart);
      });

      tearDown(() async {
        await context.tearDown();
      });

      test('can hot restart changes ', () async {
        await context.changeInput();

        var source = await context.webDriver.pageSource;

        // Main is re-invoked which shouldn't clear the state.
        expect(source.contains('Hello World!'), isTrue);
        expect(source.contains('Gary is awesome!'), isTrue);
        // The ext.flutter.disassemble callback is invoked and waited for.
        expect(source,
            contains('start disassemble end disassemble Gary is awesome'));
      });

      test('fires isolate create/destroy events during hot restart', () async {
        var client = context.debugConnection.vmService;
        await client.streamListen('Isolate');

        var eventsDone = expectLater(
            client.onIsolateEvent,
            emitsThrough(emitsInOrder([
              _hasKind(EventKind.kIsolateExit),
              _hasKind(EventKind.kIsolateStart),
              _hasKind(EventKind.kIsolateRunnable),
            ])));

        await context.changeInput();

        await eventsDone;
      });
    });

    group('and without debugging', () {
      setUp(() async {
        await context.setUp(
            reloadConfiguration: ReloadConfiguration.hotRestart,
            enableDebugging: false);
      });

      tearDown(() async {
        await context.tearDown();
      });

      test('can hot restart changes ', () async {
        await context.changeInput();

        var source = await context.webDriver.pageSource;

        // Main is re-invoked which shouldn't clear the state.
        expect(source.contains('Hello World!'), isTrue);
        expect(source.contains('Gary is awesome!'), isTrue);
        // The ext.flutter.disassemble callback is invoked and waited for.
        expect(source,
            contains('start disassemble end disassemble Gary is awesome'));
      });
    });
  });
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
