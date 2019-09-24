// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:js';

import 'restarter.dart';

class LegacyRestarter implements Restarter {
  @override
  Future<bool> restart() async {
    var dartLibrary = context['dart_library'] as JsObject;
    dartLibrary.callMethod('reload');
    return true;
  }
}
