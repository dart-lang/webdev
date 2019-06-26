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
// import 'package:vm_service_lib/vm_service_lib.dart';
// import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'test_context.dart';

final context = TestContext();
ChromeProxyService get service => context.chromeProxyService;

Map<String, dynamic> frames1 = 
{};


void main() {
    test('frames 1', () {
      
    });

}