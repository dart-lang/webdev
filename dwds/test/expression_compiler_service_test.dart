// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';

import 'expression_compiler_service_common.dart';

void main() {
  final canaryFeatures = false;
  final experiments = const <String>[];

  group('canary: $canaryFeatures |', () {
    group('AMD module system |', () {
      final moduleFormat = ModuleFormat.amd;
      testAll(
        compilerOptions: CompilerOptions(
          moduleFormat: moduleFormat,
          canaryFeatures: canaryFeatures,
          experiments: experiments,
        ),
      );
    });

    group('DDC Library Bundle module system |', () {
      final moduleFormat = ModuleFormat.ddc;
      testAll(
        compilerOptions: CompilerOptions(
          moduleFormat: moduleFormat,
          canaryFeatures: canaryFeatures,
          experiments: experiments,
        ),
      );
    });
  });
}
