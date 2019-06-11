// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html';
import 'dart:js';

import 'package:path/path.dart' as p;

final myInstance = MyTestClass();

void main() async {
  // Long running so that we can test the pause / resume behavior.
  Timer.periodic(Duration(seconds: 1), (_) {});

  print(p.join('Hello', 'World'));

  context['inspectInstance'] = () {
    inspect(myInstance);
  };

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

  Timer.periodic(Duration(seconds: 1), (_) {
    printCount();
  });

  // Register one up front before the proxy connects, the isolate should still
  // recognize this as an available extension.
  registerExtension('ext.hello_world.existing', (_, __) => null);

  window.console.debug('Page Ready');
}

var count = 0;

// An easy location to add a breakpoint.
void printCount() {
  print('The count is ${++count}');
}

String helloString(String response) => response;
bool helloBool(bool response) => response;
num helloNum(num response) => response;
MyTestClass createObject(String message) => MyTestClass(message: message);
String messageFor(MyTestClass instance) => instance.message;
String messagesCombined(MyTestClass a, MyTestClass b) => a.message + b.message;

class MyTestClass {
  final String message;

  String notFinal;

  MyTestClass({this.message = 'world'});

  String hello() => message;
}
