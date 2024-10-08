// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:vm_service/vm_service.dart';

const isRPCError = TypeMatcher<RPCError>();

final Matcher throwsRPCError = throwsA(isRPCError);

Future<void> exitWebdev(TestProcess webdev) async {
  webdev.stdin.add(utf8.encode('[{"method":"daemon.shutdown","id":0}]\n'));
  await webdev.exitCode;
}

Future<String> waitForAppId(TestProcess webdev) async {
  var appId = '';
  while (await webdev.stdout.hasNext) {
    var line = await webdev.stdout.next;
    if (line.startsWith('[{"event":"app.started"')) {
      line = line.substring(1, line.length - 1);
      final message = json.decode(line) as Map<String, dynamic>;
      appId = message['params']['appId'] as String;
      break;
    }
  }
  assert(appId.isNotEmpty);
  return appId;
}

String? getDebugServiceUri(String line) {
  final regex = RegExp(r'Debug service listening on (?<wsUri>[^\s^\\]*)');
  final match = regex.firstMatch(line);
  if (match != null) {
    final wsUri = match.namedGroup('wsUri');
    return wsUri;
  }
  return null;
}

Future<int> findBreakpointLine(VmService vmService, String breakpointId,
    String isolateId, ScriptRef scriptRef) async {
  final script = await vmService.getObject(isolateId, scriptRef.id!) as Script;
  final lines = LineSplitter.split(script.source!).toList();
  final lineNumber =
      lines.indexWhere((l) => l.endsWith('// Breakpoint: $breakpointId'));
  if (lineNumber == -1) {
    throw StateError('Unable to find breakpoint in ${scriptRef.uri} with id '
        '$breakpointId');
  }
  return lineNumber + 1;
}
