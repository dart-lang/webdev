// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:browser_launcher/browser_launcher.dart' as browser_launcher;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../command/configuration.dart';
import 'utils.dart';

var _logger = Logger('ChromeLauncher');
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
  /// Enables chrome devtools with port [port] if specified.
  /// Uses a copy of [userDataDir] to sign into the default
  /// user profile, or starts a new session without sign in,
  /// if not specified.
  static Future<Chrome> start(List<String> urls,
      {required int port, String? userDataDir}) async {
    var signIn = false;
    String? dir;
    // Re-using the directory causes flakiness on Windows, so on that platform
    // pass null to have it create a directory.
    // Issue: https://github.com/dart-lang/webdev/issues/1545
    if (!Platform.isWindows) {
      var userDataTemp = path.join(Directory.current.absolute.path,
          '.dart_tool', 'webdev', 'chrome_user_data');
      var userDataCopy = path.join(Directory.current.absolute.path,
          '.dart_tool', 'webdev', 'chrome_user_data_copy');

      if (userDataDir != null) {
        signIn = true;
        dir = userDataCopy;
        var stopwatch = Stopwatch()..start();
        try {
          _logger.info('Copying user data directory...');
          _logger.warning(
              'Copying user data directory might take >12s on the first '
              'use of --$userDataDirFlag, and ~2-3s on subsequent runs. '
              'Run without --$userDataDirFlag to improve performance.');

          Directory(dir).createSync(recursive: true);
          await updatePath(
              path.join(userDataDir, 'Default'), path.join(dir, 'Default'));

          _logger.info(
              'Copied user data directory in ${stopwatch.elapsedMilliseconds} ms');
        } catch (e, s) {
          dir = userDataTemp;
          signIn = false;
          if (Directory(dir).existsSync()) {
            Directory(dir).deleteSync(recursive: true);
          }
          _logger.severe('Failed to copy user data directory', e, s);
          _logger.severe('Launching with temp profile instead.');
          rethrow;
        }
      }

      if (!signIn) {
        dir = userDataTemp;
        Directory(dir).createSync(recursive: true);
      }
    }

    _logger.info('Starting chrome with user data directory: $dir');
    var chrome = await browser_launcher.Chrome.startWithDebugPort(urls,
        debugPort: port, userDataDir: dir, signIn: signIn);
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

String? autoDetectChromeUserDataDirectory() {
  Directory directory;
  var home = Platform.environment['HOME'] ?? '';
  if (Platform.isMacOS) {
    directory = Directory(
        path.join(home, 'Library', 'Application Support', 'Google', 'Chrome'));
  } else if (Platform.isLinux) {
    directory = Directory(path.join(home, '.config', 'google-chrome'));
  } else {
    _logger.warning('Auto detecting chrome user data directory option is not '
        'supported for ${Platform.operatingSystem}');
    return null;
  }

  if (directory.existsSync()) {
    _logger.info('Auto detected chrome user data directory: ${directory.path}');
    return directory.path;
  }

  _logger.warning('Cannot automatically detect chrome user data directory. '
      'Directory does not exist: ${directory.path}');

  return null;
}
