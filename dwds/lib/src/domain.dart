// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';

import 'package:dwds/src/chrome_proxy_service.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger.dart';
import 'inspector.dart';
import 'sources.dart';

/// Represents an aspect of the protocol and provides a way for different parts
/// to communicate with one another.
class Domain {
  AppInspectorProvider _appInspectorProvider;

  Domain(this._appInspectorProvider);

  AppInspector get inspector => _appInspectorProvider();

  Isolate checkIsolate(String isolateId) {
    if (isolateId != inspector.isolate?.id) {
      throw ArgumentError.value(
          isolateId, 'isolateId', 'Unrecognized isolate id');
    }
    return inspector.isolate;
  }
}
