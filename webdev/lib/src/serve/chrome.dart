// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:browser_launcher/browser_launcher.dart' as browser_launcher;
import 'package:path/path.dart' as path;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

var _currentCompleter = Completer<Chrome>();

/// A class for managing an instance of Chrome.
class Chrome {
  final int debugPort;
  final browser_launcher.Chrome _chrome;
  final ChromeConnection chromeConnection;

  Chrome._(
    this.debugPort,
    this._chrome,
  ) : chromeConnection = _chrome.chromeConnection;

  Future<void> close() async {
    if (_currentCompleter.isCompleted) _currentCompleter = Completer<Chrome>();
    await _chrome.close();
  }

  /// Connects to an instance of Chrome with an open debug port.
  static Future<Chrome> fromExisting(int port) async => _connect(
      Chrome._(port, await browser_launcher.Chrome.fromExisting(port)));

  static Future<Chrome> get connectedInstance => _currentCompleter.future;

  /// Starts Chrome with the remote debug port enabled.
  ///
  /// Each url in [urls] will be loaded in a separate tab.
  static Future<Chrome> start(List<String> urls, {int port}) async {
    var dir = path.join(Directory.current.absolute.path, '.dart_tool', 'webdev',
        'chrome_user_data');
    Directory(dir).createSync(recursive: true);
    var chrome = await browser_launcher.Chrome.startWithDebugPort(urls,
        debugPort: port, userDataDir: dir);
    return _connect(Chrome._(chrome.debugPort, chrome));
  }

  static Future<Chrome> _connect(Chrome chrome) async {
    if (_currentCompleter.isCompleted) {
      throw ChromeError('Only one instance of chrome can be started.');
    }
    // The connection is lazy. Try a simple call to make sure the provided
    // connection is valid.
    try {
      await chrome._chrome.chromeConnection.getTabs();
    } catch (e) {
      await chrome.close();
      throw ChromeError(
          'Unable to connect to Chrome debug port: ${chrome.debugPort}\n $e');
    }
    _currentCompleter.complete(chrome);
    return chrome;
  }
}

class ChromeError extends Error {
  final String details;
  ChromeError(this.details);

  @override
  String toString() {
    return 'ChromeError: $details';
  }
}
