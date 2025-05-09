// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fetch_libraries_for_hot_reload_request;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'fetch_libraries_for_hot_reload_request.g.dart';

/// A request to fetch libraries for hot reload.
abstract class FetchLibrariesForHotReloadRequest
    implements Built<FetchLibrariesForHotReloadRequest, FetchLibrariesForHotReloadRequestBuilder> {
  static Serializer<FetchLibrariesForHotReloadRequest> get serializer =>
      _$fetchLibrariesForHotReloadRequestSerializer;

  /// A unique identifier for this request.
  String get id;

  FetchLibrariesForHotReloadRequest._();
  factory FetchLibrariesForHotReloadRequest([
    void Function(FetchLibrariesForHotReloadRequestBuilder) updates,
  ]) = _$FetchLibrariesForHotReloadRequest;
}
