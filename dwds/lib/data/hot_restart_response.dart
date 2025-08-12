// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library hot_restart_response;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'hot_restart_response.g.dart';

/// A response to a hot restart request.
abstract class HotRestartResponse
    implements Built<HotRestartResponse, HotRestartResponseBuilder> {
  static Serializer<HotRestartResponse> get serializer =>
      _$hotRestartResponseSerializer;

  /// The unique identifier matching the request.
  String get id;

  /// Whether the hot restart succeeded on the client.
  bool get success;

  /// An optional error message if success is false.
  @BuiltValueField(wireName: 'error')
  String? get errorMessage;

  HotRestartResponse._();
  factory HotRestartResponse([
    void Function(HotRestartResponseBuilder) updates,
  ]) = _$HotRestartResponse;
}
