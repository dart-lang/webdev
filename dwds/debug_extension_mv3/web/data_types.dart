// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'data_types.g.dart';

abstract class DevToolsOpener
    implements Built<DevToolsOpener, DevToolsOpenerBuilder> {
  static Serializer<DevToolsOpener> get serializer =>
      _$devToolsOpenerSerializer;

  factory DevToolsOpener([Function(DevToolsOpenerBuilder) updates]) =
      _$DevToolsOpener;

  DevToolsOpener._();

  bool get newWindow;
}
