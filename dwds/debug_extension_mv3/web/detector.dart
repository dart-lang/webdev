// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library detector;

import 'dart:convert';
import 'dart:html';
import 'dart:js_util';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_serializers.dart';
import 'logger.dart';
import 'messaging.dart';

const _multipleAppsAttribute = 'data-multiple-dart-apps';

void main() {
  _registerListeners();
}

void _registerListeners() {
  document.addEventListener('dart-app-ready', _onDartAppReadyEvent);
  document.addEventListener('dart-auth-response', _onDartAuthEvent);
}

Future<void> _onDartAppReadyEvent(Event event) async {
  final debugInfo = getProperty(event, 'detail') as String?;
  if (debugInfo == null) {
    debugWarn(
      'No debug info sent with ready event, instead reading from Window.',
    );
    _injectDebugInfoScript();
  } else {
    await _sendMessageToBackgroundScript(
      type: MessageType.debugInfo,
      body: debugInfo,
    );
    _sendAuthRequest(debugInfo);
    _detectMultipleDartApps();
  }
}

Future<void> _onDartAuthEvent(Event event) async {
  final isAuthenticated = getProperty(event, 'detail') as String?;
  if (isAuthenticated == null) return;
  await _sendMessageToBackgroundScript(
    type: MessageType.isAuthenticated,
    body: isAuthenticated,
  );
}

void _detectMultipleDartApps() {
  final documentElement = document.documentElement;
  if (documentElement == null) return;

  if (documentElement.hasAttribute(_multipleAppsAttribute)) {
    _sendMessageToBackgroundScript(
      type: MessageType.multipleAppsDetected,
      body: 'true',
    );
    return;
  }

  final multipleAppsObserver =
      MutationObserver(_detectMultipleDartAppsCallback);
  multipleAppsObserver.observe(
    documentElement,
    attributeFilter: [_multipleAppsAttribute],
  );
}

void _detectMultipleDartAppsCallback(
  List<dynamic> mutations,
  MutationObserver observer,
) {
  for (var mutation in mutations) {
    if (_isMultipleAppsMutation(mutation)) {
      _sendMessageToBackgroundScript(
        type: MessageType.multipleAppsDetected,
        body: 'true',
      );
      observer.disconnect();
    }
  }
}

bool _isMultipleAppsMutation(dynamic mutation) {
  final isAttributeMutation = hasProperty(mutation, 'type') &&
      getProperty(mutation, 'type') == 'attributes';
  if (isAttributeMutation) {
    return hasProperty(mutation, 'attributeName') &&
        getProperty(mutation, 'attributeName') == _multipleAppsAttribute;
  }
  return false;
}

// TODO(elliette): Remove once DWDS 17.0.0 is in Flutter stable. If we are on an
// older version of DWDS, then the debug info is not sent along with the ready
// event. Therefore we must read it from the Window object, which is slower.
void _injectDebugInfoScript() {
  final script = document.createElement('script');
  final scriptSrc = chrome.runtime.getURL('debug_info.dart.js');
  script.setAttribute('src', scriptSrc);
  script.setAttribute('defer', true);
  document.head?.append(script);
}

Future<void> _sendMessageToBackgroundScript({
  required MessageType type,
  required String body,
}) async {
  await sendRuntimeMessage(
    type: type,
    body: body,
    sender: Script.detector,
    recipient: Script.background,
  );
}

void _sendAuthRequest(String debugInfoJson) {
  final debugInfo =
      serializers.deserialize(jsonDecode(debugInfoJson)) as DebugInfo?;
  final appOrigin = debugInfo?.appOrigin;
  if (appOrigin != null) {
    window.postMessage('dart-auth-request', appOrigin);
  }
}
