// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

import '../test_utils.dart';

Future<void> exitWebdev(TestProcess webdev) async {
  print('about to exit');
  webdev.stdin.add(utf8.encode('[{"method":"daemon.shutdown","id":0}]\n'));
  await webdev.exitCode;
  print('exiting');
}

Future<String> waitForAppId(TestProcess webdev) async {
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

Future<String> prepareWorkspace() async {
  var exampleDirectory = p.absolute(p.join(p.current, '..', 'example'));

  var process = await TestProcess.start(pubPath, ['upgrade'],
      workingDirectory: exampleDirectory, environment: getPubEnvironment());

  await process.shouldExit(0);
  return exampleDirectory;
}
