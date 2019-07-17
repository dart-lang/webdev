// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'extension_request.g.dart';

/// A request to run a command on Dart Debug Extension.
abstract class ExtensionRequest
    implements Built<ExtensionRequest, ExtensionRequestBuilder> {
  static Serializer<ExtensionRequest> get serializer =>
      _$extensionRequestSerializer;

  factory ExtensionRequest([Function(ExtensionRequestBuilder) updates]) =
      _$ExtensionRequest;

  ExtensionRequest._();

  /// Identifies which completer sends this request.
  int get completerId;

  String get command;

  @nullable
  BuiltMap<String, Object> get commandParams;
}

/// A response to an [ExtensionRequest].
abstract class ExtensionResponse
    implements Built<ExtensionResponse, ExtensionResponseBuilder> {
  static Serializer<ExtensionResponse> get serializer =>
      _$extensionResponseSerializer;

  factory ExtensionResponse([Function(ExtensionResponseBuilder) updates]) =
      _$ExtensionResponse;

  ExtensionResponse._();

  /// Identifies which completer to receive the response.
  int get completerId;

  bool get success;

  String get result;

  @nullable
  String get error;
}
