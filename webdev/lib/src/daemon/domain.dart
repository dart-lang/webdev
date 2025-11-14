// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'daemon.dart';
import 'utilites.dart';

/// Hosts a set of commands and events to be used with the Daemon.
abstract class Domain {
  Domain(this.daemon, this.name);

  final Daemon daemon;
  final String name;
  final Map<String, CommandHandler> _handlers = <String, CommandHandler>{};

  void registerHandler(String name, CommandHandler handler) {
    _handlers[name] = handler;
  }

  @override
  String toString() => name;

  void handleCommand(String command, Object? id, Map<String, Object?> args) {
    Future<Object?>.sync(() {
          if (_handlers.containsKey(command)) return _handlers[command]!(args);
          throw ArgumentError('command not understood: $name.$command');
        })
        .then<void>((Object? result) {
          if (result == null) {
            _send(<String, Object?>{'id': id});
          } else {
            _send(<String, Object?>{'id': id, 'result': toJsonable(result)});
          }
        })
        .catchError((Object? error, Object? trace) {
          _send(<String, Object?>{
            'id': id,
            'error': toJsonable(error),
            'trace': '$trace',
          });
        });
  }

  void sendEvent(String name, [Object? args]) {
    final map = <String, Object?>{'event': name};
    if (args != null) map['params'] = toJsonable(args);
    _send(map);
  }

  void _send(Map<String, Object?> map) => daemon.send(map);

  void dispose() {}
}

typedef CommandHandler = Future<Object?> Function(Map<String, Object?> args);
