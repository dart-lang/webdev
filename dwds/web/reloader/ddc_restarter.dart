// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:html';
import 'dart:js_util';

import '../promise.dart';
import 'restarter.dart';

class DdcRestarter implements Restarter {
  @override
  Future<bool> restart({String? runId, Future? readyToRunMain}) async {
    final dartLibrary = getProperty(globalThis, 'dart_library');
    if (runId == null && readyToRunMain == null) {
      callMethod(dartLibrary, 'reload', []);
    } else {
      final restartConfig = {
        if (runId != null) 'runId': runId,
        if (readyToRunMain != null) 'readyToRunMain': toPromise(readyToRunMain),
      };
      callMethod(dartLibrary, 'reload', [jsify(restartConfig)]);
    }
    final reloadCompleter = Completer<bool>();
    final sub = window.onMessage.listen((event) {
      final message = event.data;
      if (message is Map &&
          message['type'] == 'DDC_STATE_CHANGE' &&
          message['state'] == 'restart_end') {
        reloadCompleter.complete(true);
      }
    });
    return reloadCompleter.future.then((value) {
      sub.cancel();
      return value;
    });
  }
}
