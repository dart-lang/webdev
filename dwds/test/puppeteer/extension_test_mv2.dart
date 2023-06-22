// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@OnPlatform({
  // TODO(elliette): Enable CI testing.
  'linux': Skip('https://github.com/dart-lang/webdev/issues/1787'),
})
@Timeout(Duration(minutes: 5))
import 'package:test/test.dart';

import 'extension_common.dart';

void main() {
  testAll(
    isMV3: false,
    // TODO(elliette): Configure screenshot diffing.
    screenshotsEnabled: false,
  );
}
