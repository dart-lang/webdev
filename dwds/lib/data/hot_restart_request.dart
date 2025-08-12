// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library hot_restart_request;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'hot_restart_request.g.dart';

/// A request to hot restart the application.
abstract class HotRestartRequest
    implements Built<HotRestartRequest, HotRestartRequestBuilder> {
  static Serializer<HotRestartRequest> get serializer =>
      _$hotRestartRequestSerializer;

  /// A unique identifier for this request.
  String get id;

  HotRestartRequest._();
  factory HotRestartRequest([void Function(HotRestartRequestBuilder) updates]) =
      _$HotRestartRequest;
}
