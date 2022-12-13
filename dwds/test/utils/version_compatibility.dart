// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../fixtures/context.dart';

bool get versionSupportsWeakNullSafety =>
    Version.parse(Platform.version.split(' ')[0]).major < 3;

List<NullSafety> get supportedNullSafetyModes {
  return versionSupportsWeakNullSafety
      ? [NullSafety.sound, NullSafety.weak]
      : [NullSafety.sound];
}

// TODO(https://github.com/dart-lang/webdev/issues/1591): Frontend server
// compilation is currently incompatible with sound null safety.
List<CompilationMode> supportedCompilationModes(NullSafety nullSafetyMode) {
  return nullSafetyMode == NullSafety.sound
      ? [CompilationMode.buildDaemon]
      : [
          CompilationMode.buildDaemon,
          CompilationMode.frontendServer,
        ];
}

bool supportedMode(
    {required CompilationMode compilationMode,
    required NullSafety nullSafetyMode}) {
  final isDart3 = Version.parse(Platform.version.split(' ')[0]).major == 3;
  // TODO(https://github.com/dart-lang/webdev/issues/1818): Support compiling to
  // to weak null-safety for both FrontendServer and BuildDaemon.
  if (isDart3 && nullSafetyMode == NullSafety.weak) {
    return false;
  }
  // TODO(https://github.com/dart-lang/webdev/issues/1591): Support compiling to
  // sound null-safety for the FrontendServer.
  if (compilationMode == CompilationMode.frontendServer &&
      nullSafetyMode == NullSafety.sound) {
    return false;
  }
  // All other modes are supported.
  return true;
}
