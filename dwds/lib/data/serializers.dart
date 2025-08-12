// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';

import 'build_result.dart';
import 'connect_request.dart';
import 'debug_event.dart';
import 'debug_info.dart';
import 'devtools_request.dart';
import 'error_response.dart';
import 'extension_request.dart';
import 'hot_reload_request.dart';
import 'hot_reload_response.dart';
import 'hot_restart_request.dart';
import 'hot_restart_response.dart';
import 'service_extension_request.dart';
import 'service_extension_response.dart';
import 'isolate_events.dart';
import 'register_event.dart';
import 'run_request.dart';

part 'serializers.g.dart';

/// Serializers for all the types used in DWDS communication.
@SerializersFor([
  BatchedEvents,
  BatchedDebugEvents,
  BuildResult,
  ConnectRequest,
  DebugEvent,
  DebugInfo,
  DevToolsRequest,
  DevToolsResponse,
  HotReloadRequest,
  HotReloadResponse,
  HotRestartRequest,
  HotRestartResponse,
  IsolateExit,
  IsolateStart,
  ExtensionRequest,
  ExtensionResponse,
  ExtensionEvent,
  ErrorResponse,
  RegisterEvent,
  RunRequest,
  ServiceExtensionRequest,
  ServiceExtensionResponse,
])
final Serializers serializers = _$serializers;
