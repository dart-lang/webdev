// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

const appName = 'webdev';

/// The path to the root directory of the SDK.
final String _sdkDir = (() {
  // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
  // "/path/to/sdk".
  var aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
  assert(FileSystemEntity.isFileSync(p.join(aboveExecutable, 'version')));
  return aboveExecutable;
})();

final String dartPath = p.join(_sdkDir, 'bin', 'dart');
final String pubSnapshot =
    p.join(_sdkDir, 'bin', 'snapshots', 'pub.dart.snapshot');
final String pubPath =
    p.join(_sdkDir, 'bin', Platform.isWindows ? 'pub.bat' : 'pub');

Future<bool> get supportsIpv6 async {
  var support = false;
  try {
    var socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv6, 0, v6Only: true);
    await socket.close();
    support = true;
  } on SocketException {
    // Assume Ipv4 support only.
  }
  return support;
}
