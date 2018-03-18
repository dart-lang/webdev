// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:webdev/src/webdev_command_runner.dart';

Future main(List<String> args) async {
  await webdevCommandRunner().run(args);
}
