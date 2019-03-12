// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'daemon.dart';
import 'domain.dart';

const String protocolVersion = '0.4.2';

/// A collection of method and events relevant to the daemon command.
class DaemonDomain extends Domain {
  DaemonDomain(Daemon daemon) : super(daemon, 'daemon') {
    registerHandler('version', version);
    registerHandler('shutdown', shutdown);

    sendEvent(
      'daemon.connected',
      <String, dynamic>{
        'version': protocolVersion,
        'pid': pid,
      },
    );
  }

  Future<String> version(Map<String, dynamic> args) {
    return Future<String>.value(protocolVersion);
  }

  Future<void> shutdown(Map<String, dynamic> args) {
    Timer.run(daemon.shutdown);
    return Future<void>.value();
  }
}
