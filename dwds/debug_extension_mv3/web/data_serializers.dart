// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/serializer.dart';
import 'package:dwds/data/debug_info.dart';

import 'data_types.dart';

part 'data_serializers.g.dart';

/// Serializers for all the data types used in the Dart Debug Extension.
@SerializersFor([
  DebugInfo,
  DevToolsOpener,
])
final Serializers serializers = _$serializers;
