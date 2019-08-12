// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Contains hard-coded test data usable for tests.

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

// ignore_for_file: prefer_single_quotes

/// Stack frames in JSON format as they would be in a Chrome 'Debugger.paused'
/// event.
///
/// This is taken from a real run, but truncated to two levels of scope and one
/// level of stack.
List<Map<String, dynamic>> frames1 = [
  {
    "callFrameId": "{\"ordinal\":0,\"injectedScriptId\":2}",
    "functionName": "",
    "functionLocation": {
      "scriptId": "69",
      "lineNumber": 88,
      "columnNumber": 72
    },
    "location": {"scriptId": "69", "lineNumber": 92, "columnNumber": 8},
    "url": "http://127.0.0.1:8081/scopes_main.ddc.js",
    "scopeChain": [
      {
        "type": "local",
        "object": {
          "type": "object",
          "className": "Object",
          "description": "Object",
          "objectId": "{\"injectedScriptId\":2,\"id\":3}"
        },
        "startLocation": {
          "scriptId": "69",
          "lineNumber": 88,
          "columnNumber": 72
        },
        "endLocation": {"scriptId": "69", "lineNumber": 93, "columnNumber": 7}
      },
      {
        "type": "closure",
        "object": {
          "type": "object",
          "className": "Object",
          "description": "Object",
          "objectId": "{\"injectedScriptId\":2,\"id\":4}"
        },
        "name": "main",
        "startLocation": {
          "scriptId": "69",
          "lineNumber": 74,
          "columnNumber": 48
        },
        "endLocation": {"scriptId": "69", "lineNumber": 100, "columnNumber": 5}
      },
      {
        "type": "closure",
        "object": {
          "type": "object",
          "className": "Object",
          "description": "Object",
          "objectId": "{\"injectedScriptId\":2,\"id\":5}"
        },
        "startLocation": {
          "scriptId": "69",
          "lineNumber": 0,
          "columnNumber": 29
        },
        "endLocation": {"scriptId": "69", "lineNumber": 126, "columnNumber": 1}
      },
      {
        "type": "global",
        "object": {
          "type": "object",
          "className": "Window",
          "description": "Window",
          "objectId": "{\"injectedScriptId\":2,\"id\":6}"
        }
      }
    ],
    "this": {"type": "undefined"}
  }
];

/// Data in the form returned from getProperties called twice on successive elements of a scope chain.
///
/// It has two variables named 'a' and 'b' in the first scope.
var variables1 = [
  WipResponse({
    'id': 1,
    'result': {
      'result': [
        {'name': 'a', 'value': null},
        {'name': 'b', 'value': null}
      ]
    }
  }),
  WipResponse({
    'id': 2,
    'result': {'result': []}
  }),
  WipResponse({
    'id': 3,
    'result': {'result': []}
  }),
];
