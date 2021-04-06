// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'devtools_request.g.dart';

/// A request to open DevTools.
abstract class DevToolsRequest
    implements Built<DevToolsRequest, DevToolsRequestBuilder> {
  static Serializer<DevToolsRequest> get serializer =>
      _$devToolsRequestSerializer;

  factory DevToolsRequest([Function(DevToolsRequestBuilder) updates]) =
      _$DevToolsRequest;

  DevToolsRequest._();

  /// Identifies a given application, across tabs/windows.
  String get appId;

  /// Identifies a given instance of an application, unique per tab/window.
  String get instanceId;

  /// Identifies the context in which evaluations should occur.
  @nullable
  int get contextId;

  /// Belongs to the tab that requests the DevTools
  @nullable
  String get tabUrl;
}

/// A response to a [DevToolsRequest].
abstract class DevToolsResponse
    implements Built<DevToolsResponse, DevToolsResponseBuilder> {
  static Serializer<DevToolsResponse> get serializer =>
      _$devToolsResponseSerializer;

  factory DevToolsResponse([Function(DevToolsResponseBuilder) updates]) =
      _$DevToolsResponse;

  DevToolsResponse._();

  bool get success;

  bool get promptExtension;

  @nullable
  String get error;
}
