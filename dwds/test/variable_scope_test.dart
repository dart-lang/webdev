// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';

import 'package:dwds/src/chrome_proxy_service.dart';
// import 'package:dwds/src/dart_uri.dart';
// import 'package:http/http.dart' as http;
// import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'test_context.dart';

final context = TestContext(directory: '../example', path: 'scopes.html', pathToServe: 'web');
ChromeProxyService get service => context.chromeProxyService;
WipConnection get tabConnection => context.tabConnection;

void main() {
  setUpAll(() async {
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  group('breakpoints', () {
    VM vm;
    Isolate isolate;
    ScriptList scripts;
    ScriptRef mainScript;

    setUp(() async {
      vm = await service.getVM();
      isolate = await service.getIsolate(vm.isolates.first.id);
      scripts = await service.getScripts(isolate.id);
      mainScript =
          scripts.scripts.firstWhere((each) => each.uri.contains('scopes_main.dart'));
    });

    test('addBreakpoint', () async {
      // TODO: Much more testing.
      var bp = await service.addBreakpoint(isolate.id, mainScript.id, 24);
      // Remove breakpoint so it doesn't impact other tests.
      await service.removeBreakpoint(isolate.id, bp.id);
      expect(bp.id, '1');
    });
  });
}
