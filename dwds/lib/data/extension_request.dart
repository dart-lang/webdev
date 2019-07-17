// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'extension_request.g.dart';

/// A request to run a command in the Dart Debug Extension.
abstract class ExtensionRequest
    implements Built<ExtensionRequest, ExtensionRequestBuilder> {
  static Serializer<ExtensionRequest> get serializer =>
      _$extensionRequestSerializer;

  factory ExtensionRequest([Function(ExtensionRequestBuilder) updates]) =
      _$ExtensionRequest;

  ExtensionRequest._();

  /// Used to associate a request with an [ExtensionResponse].
  int get id;

  String get command;

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

  /// Used to associate a response with an [ExtensionRequest].
  int get id;

  bool get success;

  /// Contains a JSON-encoded payload.
  String get result;

  @nullable
  String get error;
}
