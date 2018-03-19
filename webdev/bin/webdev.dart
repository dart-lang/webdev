// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:webdev/src/webdev_command_runner.dart';

Future main(List<String> args) async {
  try {
    await webdevCommandRunner().run(args);
  } on UsageException catch (e) {
    print(yellow.wrap(e.message));
    print(' ');
    print(e.usage);
    exitCode = ExitCode.usage.code;
  }
}
