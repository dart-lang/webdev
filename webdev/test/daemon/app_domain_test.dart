// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
@Tags(['requires-edge-sdk'])

import 'dart:async';
import 'dart:convert';

@Tags(['requires-edge-sdk'])
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../test_utils.dart';
import 'utils.dart';

Future<String> _getAppId(TestProcess webdev) async {
  var appId = '';
  while (await webdev.stdout.hasNext) {
    var line = await webdev.stdout.next;
    if (line.startsWith('[{"event":"app.started"')) {
      line = line.substring(1, line.length - 1);
      var message = json.decode(line) as Map<String, dynamic>;
      appId = message['params']['appId'] as String;
      break;
    }
  }
  assert(appId.isNotEmpty);
  return appId;
}

void main() {
  String exampleDirectory;

  setUpAll(() async {
    exampleDirectory = await prepareWorkspace();
  });

  group('AppDomain', () {
    group('Events', () {
      test('.start', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emitsThrough(startsWith('[{"event":"app.start"')));
        await exitWebdev(webdev);
      });

      test('.started', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emitsThrough(startsWith('[{"event":"app.started"')));
        await exitWebdev(webdev);
      });

      test('.debugPort', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(webdev.stdout,
            emitsThrough(startsWith('[{"event":"app.debugPort"')));
        await exitWebdev(webdev);
      });
    });

    group('Methods', () {
      test('.callServiceExtension', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        var appId = await _getAppId(webdev);
        var extensionCall = '[{"method":"app.callServiceExtension","id":0,'
            '"params" : { "appId" : "$appId", "methodName" : "ext.print"}}]';
        webdev.stdin.add(utf8.encode('$extensionCall\n'));
        // The example app sets up a service extension for printing.
        await expectLater(
            webdev.stdout,
            emitsThrough(
                startsWith('[{"event":"app.log","params":{"appId":"$appId",'
                    '"log":"Hello World\\n"}}')));
        await exitWebdev(webdev);
      });

      test('.restart', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        var appId = await _getAppId(webdev);
        var extensionCall = '[{"method":"app.restart","id":0,'
            '"params" : { "appId" : "$appId", "fullRestart" : true}}]';
        webdev.stdin.add(utf8.encode('$extensionCall\n'));
        await expectLater(webdev.stdout,
            emitsThrough(startsWith('[{"id":0,"result":{"code":0')));
        await exitWebdev(webdev);
      });
    });
  }, tags: ['webdriver']);
}
