// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';

import 'logger.dart';
import 'web_api.dart';
import 'messaging.dart';

const _authSuccessResponse = 'Dart Debug Authentication Success!';
const _authPopUpMessage = 'Authentication required.\n\nClick OK to authenticate then try again.';
const _authPageTitle = 'Dart Debug Extension Authentication';

void main() async {
  final authUrl = document.documentElement?.getAttribute('data-dart-auth-url');
  if (authUrl == null) {
    _sendIsAuthenticatedMsg(false);
  } else {
    await _authenticateUser(authUrl);
  }
}

Future<void> _authenticateUser(String authUrl) async {
  final response = await fetchRequest(authUrl);
  final responseBody = response.body ?? '';
  // Handle authentication succeeded:
  if (responseBody.contains(_authSuccessResponse)) {
    _sendIsAuthenticatedMsg(true);
  } else {
    // Handle authentication failed:
    _sendIsAuthenticatedMsg(false);
    debugError('Not authenticated: ${response.status} / $responseBody');
    if (window.confirm(_authPopUpMessage)) {
      window.open(authUrl, _authPageTitle);
    }
  }
}

void _sendIsAuthenticatedMsg(bool isAuthenticated) {
  sendRuntimeMessage(
    type: MessageType.isAuthenticated, 
    body: '$isAuthenticated', 
    sender: Script.authentication, 
    recipient: Script.background,
  );
}