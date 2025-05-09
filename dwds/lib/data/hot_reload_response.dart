// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library hot_reload_response;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'hot_reload_response.g.dart';

/// A response to a hot reload request.
abstract class HotReloadResponse
    implements Built<HotReloadResponse, HotReloadResponseBuilder> {
  static Serializer<HotReloadResponse> get serializer =>
      _$hotReloadResponseSerializer;

  /// The unique identifier matching the request.
  String get id;

  /// Whether the hot reload succeeded on the client.
  bool get success;

  /// An optional error message if success is false.
  @BuiltValueField(wireName: 'error')
  String? get errorMessage;

  HotReloadResponse._();
  factory HotReloadResponse([void Function(HotReloadResponseBuilder) updates]) =
      _$HotReloadResponse;
}
