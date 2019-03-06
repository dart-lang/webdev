// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';
import 'package:dwds/service.dart';
import 'package:dwds/src/helpers.dart';
import 'package:webdev/src/serve/chrome.dart';

/// Sets up a web app with the debug service.
///
/// - Opens up chrome with a specified app uri and the debug port enabled.
/// - Runs the proxy service on a specified host and port, or a random port if
///   not specified.
void main(List<String> args) async {
  var parser = ArgParser()
    ..addOption('app-uri')
    ..addOption('host', defaultsTo: 'localhost')
    ..addOption('port');
  var parsed = parser.parse(args);
  var appUri = parsed['app-uri'] as String;
  if (appUri == null) {
    throw ArgumentError('Must provide an --app-uri to load in chrome');
  }

  var chrome = await Chrome.start([appUri]);
  var host = parsed['host'] as String;
  int port;
  if (parsed['port'] != null) {
    port = int.parse(parsed['port'] as String);
  } else {
    port = await findUnusedPort();
  }

  await DebugService.start(host, chrome.chromeConnection, appUri);
  print('Debug service running at ws://$host:$port');
}
