// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class ConnectFailure {
  final int tabId;
  final String? reason;

  ConnectFailure({required this.tabId, this.reason});

  Map<String, dynamic> toJson() => {
    'tabId': tabId,
    if (reason != null) 'reason': reason,
  };

  factory ConnectFailure.fromJson(Map<String, dynamic> json) => ConnectFailure(
    tabId: json['tabId'] as int,
    reason: json['reason'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectFailure &&
          runtimeType == other.runtimeType &&
          tabId == other.tabId &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(tabId, reason);

  @override
  String toString() => 'ConnectFailure(tabId: $tabId, reason: $reason)';
}

class DevToolsOpener {
  final bool newWindow;

  DevToolsOpener({required this.newWindow});

  Map<String, dynamic> toJson() => {'newWindow': newWindow};

  factory DevToolsOpener.fromJson(Map<String, dynamic> json) =>
      DevToolsOpener(newWindow: json['newWindow'] as bool);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevToolsOpener &&
          runtimeType == other.runtimeType &&
          newWindow == other.newWindow;

  @override
  int get hashCode => newWindow.hashCode;

  @override
  String toString() => 'DevToolsOpener(newWindow: $newWindow)';
}

class DevToolsUrl {
  final int tabId;
  final String url;

  DevToolsUrl({required this.tabId, required this.url});

  Map<String, dynamic> toJson() => {'tabId': tabId, 'url': url};

  factory DevToolsUrl.fromJson(Map<String, dynamic> json) =>
      DevToolsUrl(tabId: json['tabId'] as int, url: json['url'] as String);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevToolsUrl &&
          runtimeType == other.runtimeType &&
          tabId == other.tabId &&
          url == other.url;

  @override
  int get hashCode => Object.hash(tabId, url);

  @override
  String toString() => 'DevToolsUrl(tabId: $tabId, url: $url)';
}

class DebugStateChange {
  static const startDebugging = 'start-debugging';
  static const stopDebugging = 'stop-debugging';
  static const failedToConnect = 'failed-to-connect';

  final int tabId;

  /// Can only be [startDebugging] or [stopDebugging].
  final String newState;
  final String? reason;

  DebugStateChange({required this.tabId, required this.newState, this.reason});

  Map<String, dynamic> toJson() => {
    'tabId': tabId,
    'newState': newState,
    if (reason != null) 'reason': reason,
  };

  factory DebugStateChange.fromJson(Map<String, dynamic> json) =>
      DebugStateChange(
        tabId: json['tabId'] as int,
        newState: json['newState'] as String,
        reason: json['reason'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebugStateChange &&
          runtimeType == other.runtimeType &&
          tabId == other.tabId &&
          newState == other.newState &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(tabId, newState, reason);

  @override
  String toString() =>
      'DebugStateChange(tabId: $tabId, newState: $newState, reason: $reason)';
}
