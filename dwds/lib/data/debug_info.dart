// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'debug_info.g.dart';

abstract class DebugInfo implements Built<DebugInfo, DebugInfoBuilder> {
  static Serializer<DebugInfo> get serializer => _$debugInfoSerializer;

  factory DebugInfo([Function(DebugInfoBuilder) updates]) = _$DebugInfo;

  DebugInfo._();

  String? get appEntrypointPath;
  String? get appId;
  String? get appInstanceId;
  String? get appOrigin;
  String? get appUrl;
  String? get dwdsVersion;
  String? get extensionUrl;
  bool? get isInternalBuild;
}
