// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';

final context = TestContext();

ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);

void main() {
  setUpAll(() async {
    await context.setUp(autoRun: false);
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('correctly sets the isolate pauseEvent', () async {
    var vm = await service.getVM();
    var isolate = await service.getIsolate(vm.isolates.first.id);
    expect(isolate.pauseEvent.kind, EventKind.kPauseStart);
    var stream = service.onEvent('Debug');
    context.appConnection.runMain();
    await stream.firstWhere((event) => event.kind == EventKind.kResume);
    expect(isolate.pauseEvent.kind, EventKind.kResume);
  });
}
