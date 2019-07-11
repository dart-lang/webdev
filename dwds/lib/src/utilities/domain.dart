// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

import '../debugging/inspector.dart';
import '../services/chrome_proxy_service.dart';

/// A common superclass to allow implementations of different parts of the
/// protocol to get access to the inspector and utility functions.
///
/// Subclasses should call the super constructor with the AppInspectorProvider.
abstract class Domain {
  final AppInspectorProvider _appInspectorProvider;

  Domain(this._appInspectorProvider);

  /// A constructor for the AppInspector to call which doesn't set
  /// [_appInspectorProvider] as it's not used by the AppInspector.
  Domain.forInspector() : _appInspectorProvider = null;

  AppInspector get inspector => _appInspectorProvider();

  /// Validate that isolateId matches the current isolate we're connected to and
  /// return that isolate.
  ///
  /// This is useful to call at the beginning of API methods that are passed an
  /// isolate id.
  Isolate checkIsolate(String isolateId) {
    if (isolateId != inspector.isolate?.id) {
      throw ArgumentError.value(
          isolateId, 'isolateId', 'Unrecognized isolate id');
    }
    return inspector.isolate;
  }
}
