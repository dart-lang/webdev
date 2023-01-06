// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'data_types.g.dart';

abstract class ConnectFailure
    implements Built<ConnectFailure, ConnectFailureBuilder> {
  static Serializer<ConnectFailure> get serializer =>
      _$connectFailureSerializer;

  factory ConnectFailure([Function(ConnectFailureBuilder) updates]) =
      _$ConnectFailure;

  ConnectFailure._();

  int get tabId;

  String? get reason;
}

abstract class DevToolsOpener
    implements Built<DevToolsOpener, DevToolsOpenerBuilder> {
  static Serializer<DevToolsOpener> get serializer =>
      _$devToolsOpenerSerializer;

  factory DevToolsOpener([Function(DevToolsOpenerBuilder) updates]) =
      _$DevToolsOpener;

  DevToolsOpener._();

  bool get newWindow;
}

// TODO(elliette): Standardize on uri or url here and across DWDS, instead of a
// combination of both.
abstract class EncodedUri implements Built<EncodedUri, EncodedUriBuilder> {
  static Serializer<EncodedUri> get serializer => _$encodedUriSerializer;

  factory EncodedUri([Function(EncodedUriBuilder) updates]) = _$EncodedUri;

  EncodedUri._();

  String get uri;
}

abstract class DevToolsUrl implements Built<DevToolsUrl, DevToolsUrlBuilder> {
  static Serializer<DevToolsUrl> get serializer => _$devToolsUrlSerializer;

  factory DevToolsUrl([Function(DevToolsUrlBuilder) updates]) = _$DevToolsUrl;

  DevToolsUrl._();

  int get tabId;

  String get url;
}

abstract class DebugStateChange
    implements Built<DebugStateChange, DebugStateChangeBuilder> {
  static const startDebugging = 'start-debugging';
  static const stopDebugging = 'stop-debugging';
  static const failedToConnect = 'failed-to-connect';

  static Serializer<DebugStateChange> get serializer =>
      _$debugStateChangeSerializer;

  factory DebugStateChange([Function(DebugStateChangeBuilder) updates]) =
      _$DebugStateChange;

  DebugStateChange._();

  int get tabId;

  /// Can only be [startDebugging] or [stopDebugging].
  String get newState;

  String? get reason;
}
