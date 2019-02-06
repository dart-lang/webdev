// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:html';

import 'package:sse/client/sse_client.dart';

// GENERATE:
// dart2js lib/src/serve/reload_client/live_reload/client.dart -o lib/src/serve/reload_client/live_reload_client.js -m
Future<void> main() async {
  var client = SseClient(r'/$sseHandler');
  client.stream.listen((_) async {
    window.location.reload();
  });
}
