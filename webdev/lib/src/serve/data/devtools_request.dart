// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'devtools_request.g.dart';

/// A request to open DevTools.
abstract class DevToolsRequest
    implements Built<DevToolsRequest, DevToolsRequestBuilder> {
  static Serializer<DevToolsRequest> get serializer =>
      _$devToolsRequestSerializer;

  factory DevToolsRequest([updates(DevToolsRequestBuilder b)]) =
      _$DevToolsRequest;

  DevToolsRequest._();

  String get url;
}
