// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns a port that is probably, but not definitely, not in use.
///
/// This has a built-in race condition: another process may bind this port at
/// any time after this call has returned.
Future<int> findUnusedPort() async {
  int port;
  ServerSocket socket;
  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
  } on SocketException {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  }
  port = socket.port;
  await socket.close();
  return port;
}

/// Copy directory [from] to [to].
///
/// Updates contents of [to] if already exists.
Future<void> updatePath(String from, String to) async {
  await _removeDeleted(from, to);
  await _copyUpdated(from, to);
}

// Update modified files.
Future<void> _copyUpdated(String from, String to) async {
  if (!Directory(from).existsSync()) return;
  await Directory(to).create(recursive: true);

  await for (final file in Directory(from).list()) {
    final copyTo = p.join(to, p.relative(file.path, from: from));
    if (file is Directory) {
      await _copyUpdated(file.path, copyTo);
    } else if (file is File) {
      var copyToFile = File(copyTo);
      if (!copyToFile.existsSync() ||
          copyToFile.statSync().modified.compareTo(file.statSync().modified) <
              0) {
        await File(file.path).copy(copyTo);
      }
    } else if (file is Link) {
      await Link(copyTo).create(await file.target(), recursive: true);
    }
  }
}

// Remove deleted files.
Future<void> _removeDeleted(String from, String to) async {
  if (!Directory(from).existsSync()) {
    if (Directory(to).existsSync()) {
      await Directory(to).delete(recursive: true);
    }
    return;
  }

  await for (final file in Directory(to).list()) {
    final copyFrom = p.join(from, p.relative(file.path, from: to));
    if (file is File) {
      var copyFromFile = File(copyFrom);
      if (!copyFromFile.existsSync()) {
        await File(file.path).delete();
      }
    } else if (file is Directory) {
      var copyFromDir = Directory(copyFrom);
      await _removeDeleted(copyFromDir.path, file.path);
    } else if (file is Link) {
      var copyFromDir = Link(copyFrom);
      if (!copyFromDir.existsSync()) {
        await Link(file.path).delete();
      }
    }
  }
}
