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

  DebugInfo({
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

  Map<String, dynamic> toJson() => {
    if (appEntrypointPath != null) 'appEntrypointPath': appEntrypointPath,
    if (appId != null) 'appId': appId,
    if (appInstanceId != null) 'appInstanceId': appInstanceId,
    if (appOrigin != null) 'appOrigin': appOrigin,
    if (appUrl != null) 'appUrl': appUrl,
    if (authUrl != null) 'authUrl': authUrl,
    if (dwdsVersion != null) 'dwdsVersion': dwdsVersion,
    if (extensionUrl != null) 'extensionUrl': extensionUrl,
    if (isInternalBuild != null) 'isInternalBuild': isInternalBuild,
    if (isFlutterApp != null) 'isFlutterApp': isFlutterApp,
    if (workspaceName != null) 'workspaceName': workspaceName,
    if (tabUrl != null) 'tabUrl': tabUrl,
    if (tabId != null) 'tabId': tabId,
  };

  factory DebugInfo.fromJson(Map<String, dynamic> json) {
    return DebugInfo(
      appEntrypointPath: json['appEntrypointPath'] as String?,
      appId: json['appId'] as String?,
      appInstanceId: json['appInstanceId'] as String?,
      appOrigin: json['appOrigin'] as String?,
      appUrl: json['appUrl'] as String?,
      authUrl: json['authUrl'] as String?,
      dwdsVersion: json['dwdsVersion'] as String?,
      extensionUrl: json['extensionUrl'] as String?,
      isInternalBuild: json['isInternalBuild'] as bool?,
      isFlutterApp: json['isFlutterApp'] as bool?,
      workspaceName: json['workspaceName'] as String?,
      tabUrl: json['tabUrl'] as String?,
      tabId: json['tabId'] as int?,
    );
  }
}
