// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fetch_libraries_for_hot_reload_response;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'fetch_libraries_for_hot_reload_response.g.dart';

/// A response to a fetch libraries for hot reload request.
abstract class FetchLibrariesForHotReloadResponse
    implements Built<FetchLibrariesForHotReloadResponse, FetchLibrariesForHotReloadResponseBuilder> {
  static Serializer<FetchLibrariesForHotReloadResponse> get serializer =>
      _$fetchLibrariesForHotReloadResponseSerializer;

  /// The unique identifier matching the request.
  String get id;

  /// Whether the fetch succeeded on the client.
  bool get success;

  /// An optional error message if success is false.
  @BuiltValueField(wireName: 'error')
  String? get errorMessage;

  FetchLibrariesForHotReloadResponse._();
  factory FetchLibrariesForHotReloadResponse([
    void Function(FetchLibrariesForHotReloadResponseBuilder) updates,
  ]) = _$FetchLibrariesForHotReloadResponse;
}
