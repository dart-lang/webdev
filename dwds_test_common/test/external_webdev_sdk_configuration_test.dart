// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:dwds_test_common/logging.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';

void main() {
  const debug = false;

  for (final format in [ModuleFormat.ddc, ModuleFormat.amd]) {
    group('External Webdev SDK configuration | ${format.name} modules |', () {
      setUpAll(() {
        setCurrentLogWriter(debug: debug);
      });

      final provider = TestSdkConfigurationProvider(
        verbose: debug,
        ddcModuleFormat: format,
      );
      tearDownAll(provider.dispose);

      test('SDK layout exists', () async {
        await provider.configuration;
        final sdkLayout = provider.sdkLayout;

        expect(sdkLayout.devToolsDirectory, _directoryExists);
        if (format == ModuleFormat.amd) {
          expect(sdkLayout.requireJsPath, _fileExists);
        }
      });
    });
  }
}

Matcher _fileExists = predicate(
  (String path) => File(path).existsSync(),
  'File exists',
);

Matcher _directoryExists = predicate(
  (String path) => Directory(path).existsSync(),
  'Directory exists',
);
