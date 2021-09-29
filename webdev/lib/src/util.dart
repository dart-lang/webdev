// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:stack_trace/stack_trace.dart';

const appName = 'webdev';

/// Handles [requests] using [handler].
///
/// Captures all sync and async stack error traces and passes
/// them to the [onError] handler.
void serveHttpRequests(Stream<HttpRequest> requests, Handler handler,
    void Function(Object, StackTrace) onError) {
  return Chain.capture(() {
    serveRequests(requests, handler);
  }, onError: onError);
}

/// The path to the root directory of the SDK.
final String _sdkDir = (() {
  // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
  // "/path/to/sdk".
  var aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
  assert(FileSystemEntity.isFileSync(p.join(aboveExecutable, 'version')));
  return aboveExecutable;
})();

final String dartPath = p.join(_sdkDir, 'bin', 'dart');
