// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register_entrypoint_request.g.dart';

/// A request to load entrypoint metadata.
abstract class RegisterEntrypointRequest
    implements
        Built<RegisterEntrypointRequest, RegisterEntrypointRequestBuilder> {
  static Serializer<RegisterEntrypointRequest> get serializer =>
      _$registerEntrypointRequestSerializer;

  factory RegisterEntrypointRequest(
          [Function(RegisterEntrypointRequestBuilder) updates]) =
      _$RegisterEntrypointRequest;

  RegisterEntrypointRequest._();

  String get appName;

  /// The entrypoint for the Dart application.
  String get entrypointPath;
}
