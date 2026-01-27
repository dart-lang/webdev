// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class DebugInfo {
  final String? appEntrypointPath;
  final String? appId;
  final String? appInstanceId;
  final String? appOrigin;
  final String? appUrl;
  final String? authUrl;
  final String? dwdsVersion;
  final String? extensionUrl;
  final bool? isInternalBuild;
  final bool? isFlutterApp;
  final String? workspaceName;
  final String? tabUrl;
  final int? tabId;

  const DebugInfo({
    this.appEntrypointPath,
    this.appId,
    this.appInstanceId,
    this.appOrigin,
    this.appUrl,
    this.authUrl,
    this.dwdsVersion,
    this.extensionUrl,
    this.isInternalBuild,
    this.isFlutterApp,
    this.workspaceName,
    this.tabUrl,
    this.tabId,
  });

  /// Mimics built_value serialization for compatibility.
  ///
  /// Returns a list in the format:
  /// ['DebugInfo', 'key1', value1, 'key2', value2, ...]
  ///
  /// Null values are omitted from the list.
  List<Object?> toJson() => [
    'DebugInfo',
    if (appEntrypointPath != null) ...['appEntrypointPath', appEntrypointPath],
    if (appId != null) ...['appId', appId],
    if (appInstanceId != null) ...['appInstanceId', appInstanceId],
    if (appOrigin != null) ...['appOrigin', appOrigin],
    if (appUrl != null) ...['appUrl', appUrl],
    if (authUrl != null) ...['authUrl', authUrl],
    if (dwdsVersion != null) ...['dwdsVersion', dwdsVersion],
    if (extensionUrl != null) ...['extensionUrl', extensionUrl],
    if (isInternalBuild != null) ...['isInternalBuild', isInternalBuild],
    if (isFlutterApp != null) ...['isFlutterApp', isFlutterApp],
    if (workspaceName != null) ...['workspaceName', workspaceName],
    if (tabUrl != null) ...['tabUrl', tabUrl],
    if (tabId != null) ...['tabId', tabId],
  ];

  factory DebugInfo.fromJson(List<dynamic> list) {
    String? appEntrypointPath;
    String? appId;
    String? appInstanceId;
    String? appOrigin;
    String? appUrl;
    String? authUrl;
    String? dwdsVersion;
    String? extensionUrl;
    bool? isInternalBuild;
    bool? isFlutterApp;
    String? workspaceName;
    String? tabUrl;
    int? tabId;

    var i = 0;
    // Handle the case where the type name is the first element
    if (list.isNotEmpty && list[0] is String && list[0] == 'DebugInfo') {
      i = 1;
    } else {
      throw FormatException('Expected "DebugInfo" as first element', list);
    }

    while (i < list.length - 1) {
      final key = list[i] as String;
      final value = list[i + 1];
      i += 2;

      switch (key) {
        case 'appEntrypointPath':
          appEntrypointPath = value as String?;
        case 'appId':
          appId = value as String?;
        case 'appInstanceId':
          appInstanceId = value as String?;
        case 'appOrigin':
          appOrigin = value as String?;
        case 'appUrl':
          appUrl = value as String?;
        case 'authUrl':
          authUrl = value as String?;
        case 'dwdsVersion':
          dwdsVersion = value as String?;
        case 'extensionUrl':
          extensionUrl = value as String?;
        case 'isInternalBuild':
          isInternalBuild = value as bool?;
        case 'isFlutterApp':
          isFlutterApp = value as bool?;
        case 'workspaceName':
          workspaceName = value as String?;
        case 'tabUrl':
          tabUrl = value as String?;
        case 'tabId':
          tabId = value as int?;
      }
    }

    return DebugInfo(
      appEntrypointPath: appEntrypointPath,
      appId: appId,
      appInstanceId: appInstanceId,
      appOrigin: appOrigin,
      appUrl: appUrl,
      authUrl: authUrl,
      dwdsVersion: dwdsVersion,
      extensionUrl: extensionUrl,
      isInternalBuild: isInternalBuild,
      isFlutterApp: isFlutterApp,
      workspaceName: workspaceName,
      tabUrl: tabUrl,
      tabId: tabId,
    );
  }
}
