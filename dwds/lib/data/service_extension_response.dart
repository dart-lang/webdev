// Copyright (c) 2025, the Dart project authors. All rights reserved.
// Defines the response for service extension calls over WebSocket.

import 'dart:convert';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_extension_response.g.dart';

abstract class ServiceExtensionResponse
    implements
        Built<ServiceExtensionResponse, ServiceExtensionResponseBuilder> {
  String get id;
  String?
  get resultJson; // Store result as JSON string for built_value compatibility
  bool get success;
  int? get errorCode;
  String? get errorMessage;

  // Helper method to get result as Map<String, dynamic>
  Map<String, dynamic>? get result =>
      resultJson == null || resultJson!.isEmpty
          ? null
          : json.decode(resultJson!) as Map<String, dynamic>;

  ServiceExtensionResponse._();
  factory ServiceExtensionResponse([
    void Function(ServiceExtensionResponseBuilder) updates,
  ]) = _$ServiceExtensionResponse;

  // Convenient factory method to create with result Map
  factory ServiceExtensionResponse.fromResult({
    required String id,
    required bool success,
    Map<String, dynamic>? result,
    int? errorCode,
    String? errorMessage,
  }) => ServiceExtensionResponse(
    (b) =>
        b
          ..id = id
          ..success = success
          ..resultJson = result != null ? json.encode(result) : null
          ..errorCode = errorCode
          ..errorMessage = errorMessage,
  );

  static Serializer<ServiceExtensionResponse> get serializer =>
      _$serviceExtensionResponseSerializer;
}
