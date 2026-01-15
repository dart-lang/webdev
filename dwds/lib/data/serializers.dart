// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';

import 'debug_info.dart';
import 'devtools_request.dart';
import 'extension_request.dart';
import 'isolate_events.dart';
import 'run_request.dart';

part 'serializers.g.dart';

/// Serializers for all the types used in DWDS communication.
@SerializersFor([
  BatchedEvents,
  DevToolsRequest,
  DevToolsResponse,
  ExtensionRequest,
  ExtensionResponse,
  ExtensionEvent,
])
final Serializers serializers = _$serializers;
