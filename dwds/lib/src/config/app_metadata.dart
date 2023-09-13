// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Metadata for the connected app.
///
/// These are set by the code runner and passed to DWDS on start up.
class AppMetadata {
  final String hostname;
  final bool isInternalBuild;
  Future<bool> Function() isFlutterApp;

  AppMetadata({
    this.hostname = 'localhost',
    this.isInternalBuild = false,
    Future<bool> Function()? isFlutterApp,
  }) : isFlutterApp = isFlutterApp ?? (() => Future.value(true));
}
