// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../fixtures/context.dart';

List<NullSafety> supportedNullSafetyModes() {
  final sdkVersion = Version.parse(Platform.version.split(' ')[0]);
  return (sdkVersion.major >= 3)
      ? [NullSafety.sound]
      : [NullSafety.sound, NullSafety.weak];
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
