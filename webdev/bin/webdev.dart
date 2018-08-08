// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:webdev/src/webdev_command_runner.dart';

Future main(List<String> args) async {
  try {
    exitCode = await run(args);
  } on UsageException catch (e) {
    print(red.wrap(e.message));
    print(' ');
    print(e.usage);
    exitCode = ExitCode.usage.code;
  } on FileSystemException catch (e) {
    print(red.wrap('$_boldApp could not run in the current directory.'));
    print(e.message);
    if (e.path != null) {
      print('  ${e.path}');
    }
    exitCode = ExitCode.config.code;
  } on PackageException catch (e) {
    var withUnsupportedArg =
        e.unsupportedArgument != null ? ' with --${e.unsupportedArgument}' : '';
    print(red
        .wrap('$_boldApp could not run$withUnsupportedArg for this project.'));
    for (var detail in e.details) {
      print(yellow.wrap(detail.error));
      if (detail.description != null) {
        print(detail.description);
      }
    }

    exitCode = ExitCode.config.code;
  } on IsolateSpawnException catch (e) {
    print(red.wrap('$_boldApp failed with an unexpected exception.'));
    print(e.message);
    exitCode = ExitCode.software.code;
  }
}

String get _boldApp => styleBold.wrap(appName);
