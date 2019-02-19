// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'utils.dart';

const _linuxExecutable = 'google-chrome';
const _macOSExecutable =
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const _windowsExecutable = r'Google\Chrome\Application\chrome.exe';

String get _executable {
  if (Platform.isLinux) return _linuxExecutable;
  if (Platform.isMacOS) return _macOSExecutable;
  if (Platform.isWindows) return _windowsExecutable;
  throw StateError('Unexpected platform type.');
}

/// A class for managing an instance of Chrome.
class Chrome {
  final int debugPort;
  final Process _process;
  final Directory _dataDir;

  Chrome._(this.debugPort, this._process, this._dataDir);

  Future<void> close() async {
    _process.kill();
    await _dataDir.delete(recursive: true);
  }

  /// Starts Chrome with the remote debug port enabled.
  ///
  /// Each url in [urls] will be loaded in a separate tab.
  static Future<Chrome> start(List<String> urls) async {
    var dataDir = Directory.systemTemp.createTempSync();
    var port = await findUnusedPort();
    var args = [
      // Using a tmp directory ensures that a new instance of chrome launches
      // allowing for the remote debug port to be enabled.
      '--user-data-dir=${dataDir.path}',
      '--remote-debugging-port=$port',
      // Since we are using a temp profile, disable features that slow the
      // Chrome launch.
      '--disable-extensions',
      '--disable-popup-blocking',
      '--bwsi',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-default-apps',
      '--disable-translate',
    ]..addAll(urls);

    var process = await Process.start(_executable, args);
    return Chrome._(port, process, dataDir);
  }
}
