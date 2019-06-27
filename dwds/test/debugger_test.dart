// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';

// import 'package:dwds/src/chrome_proxy_service.dart';
import 'package:dwds/src/debugger.dart';
import 'package:dwds/src/inspector.dart';
// import 'package:dwds/src/dart_uri.dart';
// import 'package:http/http.dart' as http;
// import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
// import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'test_context.dart';

// ignore_for_file: prefer_single_quotes

final context = TestContext();
// ChromeProxyService get service => context.chromeProxyService;
AppInspector inspector;
Debugger debugger;

List<Map<String, dynamic>> frames1a = 
[  
   {  
      "callFrameId":"{\"ordinal\":0,\"injectedScriptId\":2}",
      "functionName":"",
      "functionLocation":{  
         "scriptId":"69",
         "lineNumber":88,
         "columnNumber":72
      },
      "location":{  
         "scriptId":"69",
         "lineNumber":92,
         "columnNumber":8
      },
      "url":"http://127.0.0.1:8081/scopes_main.ddc.js",
      "scopeChain":[  
         {  
            "type":"local",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":3}"
            },
            "startLocation":{  
               "scriptId":"69",
               "lineNumber":88,
               "columnNumber":72
            },
            "endLocation":{  
               "scriptId":"69",
               "lineNumber":93,
               "columnNumber":7
            }
         },
         {  
            "type":"closure",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":4}"
            },
            "name":"main",
            "startLocation":{  
               "scriptId":"69",
               "lineNumber":74,
               "columnNumber":48
            },
            "endLocation":{  
               "scriptId":"69",
               "lineNumber":100,
               "columnNumber":5
            }
         },
         {  
            "type":"closure",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":5}"
            },
            "startLocation":{  
               "scriptId":"69",
               "lineNumber":0,
               "columnNumber":29
            },
            "endLocation":{  
               "scriptId":"69",
               "lineNumber":126,
               "columnNumber":1
            }
         },
         {  
            "type":"global",
            "object":{  
               "type":"object",
               "className":"Window",
               "description":"Window",
               "objectId":"{\"injectedScriptId\":2,\"id\":6}"
            }
         }
      ],
      "this":{  
         "type":"undefined"
      }
   },
   {  
      "callFrameId":"{\"ordinal\":1,\"injectedScriptId\":2}",
      "functionName":"",
      "functionLocation":{  
         "scriptId":"18",
         "lineNumber":15639,
         "columnNumber":65
      },
      "location":{  
         "scriptId":"18",
         "lineNumber":15648,
         "columnNumber":8
      },
      "url":"http://127.0.0.1:8081/packages/build_web_compilers/src/dev_compiler/dart_sdk.js",
      "scopeChain":[  
         {  
            "type":"local",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":7}"
            },
            "startLocation":{  
               "scriptId":"18",
               "lineNumber":15639,
               "columnNumber":65
            },
            "endLocation":{  
               "scriptId":"18",
               "lineNumber":15649,
               "columnNumber":7
            }
         },
         {  
            "type":"block",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":8}"
            },
            "name":"_isolate_helper.TimerImpl.periodic",
            "startLocation":{  
               "scriptId":"18",
               "lineNumber":15632,
               "columnNumber":48
            },
            "endLocation":{  
               "scriptId":"18",
               "lineNumber":15653,
               "columnNumber":3
            }
         },
         {  
            "type":"closure",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":9}"
            },
            "name":"_isolate_helper.TimerImpl.periodic",
            "startLocation":{  
               "scriptId":"18",
               "lineNumber":15632,
               "columnNumber":48
            },
            "endLocation":{  
               "scriptId":"18",
               "lineNumber":15653,
               "columnNumber":3
            }
         },
         {  
            "type":"closure",
            "object":{  
               "type":"object",
               "className":"Object",
               "description":"Object",
               "objectId":"{\"injectedScriptId\":2,\"id\":10}"
            },
            "startLocation":{  
               "scriptId":"18",
               "lineNumber":0,
               "columnNumber":19
            },
            "endLocation":{  
               "scriptId":"18",
               "lineNumber":124409,
               "columnNumber":1
            }
         },
         {  
            "type":"global",
            "object":{  
               "type":"object",
               "className":"Window",
               "description":"Window",
               "objectId":"{\"injectedScriptId\":2,\"id\":11}"
            }
         }
      ],
      "this":{  
         "type":"undefined"
      }
   }
];


List<Map<String, dynamic>> frames1b = [
  {
    "type": "local",
    "object": {
      "type": "object",
      "className": "Object",
      "description": "Object",
      "objectId": "{\"injectedScriptId\":2,\"id\":3}"
    },
    "startLocation": {"scriptId": "69", "lineNumber": 88, "columnNumber": 72},
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
    "startLocation": {"scriptId": "69", "lineNumber": 74, "columnNumber": 48},
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
    "startLocation": {"scriptId": "69", "lineNumber": 0, "columnNumber": 29},
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
];

class FakeWipConnection implements WipConnection {
  @override
  Future close() async {}
  @override
  Future<WipResponse> sendCommand(String method,
      [Map<String, dynamic> foo]) async {
    return null;
  }

  @override
  WipConsole get console => null; // ignore: deprecated_member_use
  @override
  WipDebugger get debugger => null;
  @override
  WipDom get dom => null;
  @override
  WipLog get log => null;
  @override
  Stream<WipConnection> get onClose => null;
  @override
  Stream<WipEvent> get onNotification => null;
  @override
  WipPage get page => null;
  @override
  WipRuntime get runtime => null;
  @override
  WipTarget get target => null;
  @override
  String get url => null;
}

void main() async {
  setUpAll(() async {
    debugger = await Debugger.create(
        null, FakeWipConnection(), null, () => inspector, 'fakeRoot');
  });

  test('frames 1', () async {
    var frames = await debugger.dartFramesFor(frames1a);
    expect(frames, isNotNull);
  });
}
