// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:stack_trace/stack_trace.dart';

const appName = 'webdev';

/// Handles [requests] using [handler].
///
/// Captures all sync and async stack error traces and passes
/// them to the [onError] handler.
void serveHttpRequests(
  Stream<HttpRequest> requests,
  Handler handler,
  void Function(Object, StackTrace) onError,
) {
  return Chain.capture(() {
    serveRequests(requests, handler);
  }, onError: onError);
}

final String dartPath =
    cli_util.dartExecutable ??
    (throw StateError('Unable to locate the Dart SDK.'));
