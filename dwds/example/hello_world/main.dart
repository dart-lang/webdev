// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html';
import 'dart:js';

import 'package:path/path.dart' as p;

void main() async {
  // Long running so that we can test the pause / resume behavior.
  Timer.periodic(Duration(seconds: 1), (_) {});

  print(p.join('Hello', 'World'));

  context['postEvent'] = (String kind) {
    postEvent(kind, {'example': 'data'});
  };

  context['registerExtension'] = (String method) {
    registerExtension(method,
        (String method, Map<String, String> parameters) async {
      return ServiceExtensionResponse.result(jsonEncode(parameters ?? {}));
    });
  };

  context['registerExtensionWithError'] = (String method) {
    registerExtension(method,
        (String method, Map<String, String> parameters) async {
      return ServiceExtensionResponse.error(
          int.parse(parameters['code']), parameters['details']);
    });
  };

  // Register one up front before the proxy connects, the isolate should still
  // recognize this as an available extension.
  registerExtension('ext.hello_world.existing', (_, __) {});

  window.console.debug('Page Ready');
}

String helloString(String response) => response;
bool helloBool(bool response) => response;
num helloNum(num response) => response;

class MyTestClass {
  String hello() => 'world';
}
