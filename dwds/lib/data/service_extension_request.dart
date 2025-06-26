// Copyright (c) 2025, the Dart project authors. All rights reserved.
// Defines the request for service extension calls over WebSocket.

import 'dart:convert';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_extension_request.g.dart';

abstract class ServiceExtensionRequest
    implements Built<ServiceExtensionRequest, ServiceExtensionRequestBuilder> {
  String get id;
  String get method;
  String
  get argsJson; // Store args as JSON string for built_value compatibility

  // Helper method to get args as Map<String, dynamic>
  Map<String, dynamic> get args =>
      argsJson.isEmpty
          ? <String, dynamic>{}
          : json.decode(argsJson) as Map<String, dynamic>;

  ServiceExtensionRequest._();
  factory ServiceExtensionRequest([
    void Function(ServiceExtensionRequestBuilder) updates,
  ]) = _$ServiceExtensionRequest;

  // Convenient factory method to create with args Map
  factory ServiceExtensionRequest.fromArgs({
    required String id,
    required String method,
    required Map<String, dynamic> args,
  }) => ServiceExtensionRequest(
    (b) =>
        b
          ..id = id
          ..method = method
          ..argsJson = json.encode(args),
  );

  static Serializer<ServiceExtensionRequest> get serializer =>
      _$serviceExtensionRequestSerializer;
}
