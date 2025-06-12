// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'restarter.dart';

@anonymous
@JS()
@staticInterop
class DartLibrary {}

@JS(r'dart_library')
external DartLibrary dartLibrary;

extension DartLibraryExtension on DartLibrary {
  external void reload(String? runId, JSPromise? readyToRunMain);
}

class DdcRestarter implements Restarter {
  @override
  Future<bool> restart({String? runId, Future? readyToRunMain}) async {
    dartLibrary.reload(runId, readyToRunMain?.toJS);
    final reloadCompleter = Completer<bool>();
    final sub = window.onMessage.listen((event) {
      final message = event.data?.dartify();
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

  @override
  Future<void> hotReloadEnd() =>
      throw UnimplementedError(
        'Hot reload is not supported for the DDC module format.',
      );

  @override
  Future<JSArray<JSString>> hotReloadStart(String hotReloadSourcesPath) =>
      throw UnimplementedError(
        'Hot reload is not supported for the DDC module format.',
      );
}
