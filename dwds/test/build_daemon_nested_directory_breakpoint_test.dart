// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:async';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext(
    directory: '../fixtures/_test',
    entry: '../fixtures/_test/example/hello_world/main.dart',
    path: 'hello_world/index.html',
    pathToServe: 'example');

ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);
WipConnection get tabConnection => context.tabConnection;

void main() {
  group('shared context with evaluation', () {
    setUpAll(() async {
      await context.setUp();
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('breakpoint', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;
      Stream<Event> stream;

      setUp(() async {
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        scripts = await service.getScripts(isolate.id);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      tearDown(() async {
        await service.resume(isolate.id);
      });

      test('set breakpoint', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        expect(bp, isNotNull);

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });

      test('set breakpoint again', () async {
        var line = await context.findBreakpointLine(
            'printLocal', isolate.id, mainScript);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, line);

        await stream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        expect(bp, isNotNull);

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
      });
    });
  });
}
