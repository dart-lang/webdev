// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../fixtures/context.dart';

bool supportedMode(
    {required CompilationMode compilationMode,
    required NullSafety nullSafetyMode}) {
  // TODO(https://github.com/dart-lang/webdev/issues/1591): Support compiling to
  // sound null-safety for the FrontendServer.
  if (compilationMode == CompilationMode.frontendServer &&
      nullSafetyMode == NullSafety.sound) {
    return false;
  }
  // All other modes are supported.
  return true;
}
