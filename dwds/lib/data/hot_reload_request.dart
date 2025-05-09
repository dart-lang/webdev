// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library hot_reload_request;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'hot_reload_request.g.dart';

/// A request to hot reload the application.
abstract class HotReloadRequest
    implements Built<HotReloadRequest, HotReloadRequestBuilder> {
  static Serializer<HotReloadRequest> get serializer =>
      _$hotReloadRequestSerializer;

  /// A unique identifier for this request.
  String get id;

  HotReloadRequest._();
  factory HotReloadRequest([void Function(HotReloadRequestBuilder) updates]) =
      _$HotReloadRequest;
}
