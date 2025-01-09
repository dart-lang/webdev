// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:developer';
import 'dart:js';

// Create a series of top level objects for tests in
// dwds/test/chrome_proxy_service_ddc_library_bundle_test.dart

void main() async {
  context['registerExtension'] = (String method) {
    registerExtension(method,
        (String method, Map<String, String> parameters) async {
      return ServiceExtensionResponse.result(jsonEncode(parameters));
    });
  };

  context['registerExtensionWithError'] = (String method) {
    registerExtension(method,
        (String method, Map<String, String> parameters) async {
      return ServiceExtensionResponse.error(
          int.parse(parameters['code']!), parameters['details']!);
    });
  };
}
