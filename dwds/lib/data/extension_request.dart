// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';

const authenticationPath = '\$dwdsExtensionAuthentication';

/// A request to run a command in the Dart Debug Extension.
class ExtensionRequest {
  /// Used to associate a request with an [ExtensionResponse].
  final int id;

  final String command;

  /// Contains JSON-encoded parameters, if available.
  final String? commandParams;

  ExtensionRequest({
    required this.id,
    required this.command,
    this.commandParams,
  });

  factory ExtensionRequest.fromJson(Map<String, dynamic> json) {
    return ExtensionRequest(
      id: json['id'] as int,
      command: json['command'] as String,
      commandParams: json['commandParams'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'command': command,
      if (commandParams != null) 'commandParams': commandParams,
    };
  }

  @override
  String toString() =>
      'ExtensionRequest { id=$id, command=$command, commandParams=$commandParams }';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionRequest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          command == other.command &&
          commandParams == other.commandParams;

  @override
  int get hashCode => Object.hash(id, command, commandParams);
}

/// A response to an [ExtensionRequest].
class ExtensionResponse {
  /// Used to associate a response with an [ExtensionRequest].
  final int id;

  final bool success;

  /// Contains a JSON-encoded payload.
  final String result;

  /// Contains an error, if available.
  final String? error;

  ExtensionResponse({
    required this.id,
    required this.success,
    required this.result,
    this.error,
  });

  factory ExtensionResponse.fromJson(Map<String, dynamic> json) {
    return ExtensionResponse(
      id: json['id'] as int,
      success: json['success'] as bool,
      result: json['result'] as String,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'success': success,
      'result': result,
      if (error != null) 'error': error,
    };
  }

  @override
  String toString() =>
      'ExtensionResponse { id=$id, success=$success, result=$result, error=$error }';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionResponse &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          success == other.success &&
          result == other.result &&
          error == other.error;

  @override
  int get hashCode => Object.hash(id, success, result, error);
}

/// An event for Dart Debug Extension.
class ExtensionEvent {
  /// Contains a JSON-encoded payload.
  final String params;

  final String method;

  ExtensionEvent({required this.params, required this.method});

  factory ExtensionEvent.fromJson(Map<String, dynamic> json) {
    return ExtensionEvent(
      params: json['params'] as String,
      method: json['method'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'params': params, 'method': method};
  }

  @override
  String toString() => 'ExtensionEvent { params=$params, method=$method }';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionEvent &&
          runtimeType == other.runtimeType &&
          params == other.params &&
          method == other.method;

  @override
  int get hashCode => Object.hash(params, method);
}

/// A batched group of events, currently always Debugger.scriptParsed
class BatchedEvents {
  final List<ExtensionEvent> events;

  BatchedEvents({required this.events});

  factory BatchedEvents.fromJson(Map<String, dynamic> json) {
    return BatchedEvents(
      events: (json['events'] as List)
          .map((e) => ExtensionEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'events': events.map((e) => e.toJson()).toList()};
  }

  @override
  String toString() => 'BatchedEvents { events=$events }';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchedEvents &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(events, other.events);

  @override
  int get hashCode => Object.hashAll(events);
}
