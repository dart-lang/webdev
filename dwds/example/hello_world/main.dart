// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:developer';
import 'dart:html';
import 'dart:js';

void main() async {
  context['postEvent'] = (String kind) {
    postEvent(kind, {'example': 'data'});
  };

  context['registerExtension'] = (String method) {
    registerExtension(method,
        (String method, Map<String, String> parameters) async {
      return ServiceExtensionResponse.result(
          jsonEncode({'example': 'response'}));
    });
  };

  // Help with flakyness on travis, don't fire this event right away.
  await Future.delayed(Duration(seconds: 1));
  window.console.debug('Page Ready');
}
