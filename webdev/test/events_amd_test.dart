// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:dwds/src/events.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/integration/events.dart';
import 'package:dwds_test_common/logging.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';

void main() {
  final provider = TestSdkConfigurationProvider();
  tearDownAll(provider.dispose);

  group('Build Daemon', () {
    testWithDwds(
      provider: provider,
      compilationMode: CompilationMode.buildDaemon,
    );
  });
}
