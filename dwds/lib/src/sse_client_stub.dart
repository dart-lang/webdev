// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// A stub for `package:sse/client/sse_client.dart`'s `SseClient`, used on
/// platforms where it is unavailable (such as the VM).
class SseClient {
  SseClient(String serverUrl, {String? debugKey}) {
    throw UnsupportedError('SseClient is only supported on the web.');
  }

  StreamSink<String> get sink => throw UnsupportedError('SseClient.sink');

  Stream<String> get stream => throw UnsupportedError('SseClient.stream');

  void close() => throw UnsupportedError('SseClient.close');
}
