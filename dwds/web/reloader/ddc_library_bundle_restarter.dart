// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'restarter.dart';

class DdcLibraryBundleRestarter implements Restarter {
  @override
  Future<bool> restart({String? runId, Future? readyToRunMain}) async {
    throw UnimplementedError(
        "Hot reload isn't supported for the DDC library bundle format yet.");
  }
}
