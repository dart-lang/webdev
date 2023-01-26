// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library authentication;

import 'dart:async';
import 'dart:html';
import 'dart:js_util' as js_util;

import 'package:js/js.dart';

Future<bool> authenticateUser(String authUrl) async {
  final response = await _fetchRequest(authUrl);
  final responseBody = response.body ?? '';
  return responseBody.contains('Dart Debug Authentication Success!');
}

Future<FetchResponse> _fetchRequest(String resourceUrl) async {
  try {
    final options = FetchOptions(
      method: 'GET',
      credentials: 'include',
    );
    final response =
        await promiseToFuture(_nativeJsFetch(resourceUrl, options));
    final body =
        await promiseToFuture(js_util.callMethod(response, 'text', []));
    final ok = js_util.getProperty<bool>(response, 'ok');
    final status = js_util.getProperty<int>(response, 'status');
    return FetchResponse(status: status, ok: ok, body: body);
  } catch (error) {
    return FetchResponse(
        status: 400, ok: false, body: 'Error fetching $resourceUrl: $error');
  }
}

// Custom implementation of Fetch API until the Dart implementation supports
// credentials. See https://github.com/dart-lang/http/issues/595.
@JS('fetch')
external Object _nativeJsFetch(String resourceUrl, FetchOptions options);

@JS()
@anonymous
class FetchOptions {
  external factory FetchOptions({
    required String method, // e.g., 'GET', 'POST'
    required String credentials, // e.g., 'omit', 'same-origin', 'include'
  });
}

class FetchResponse {
  final int status;
  final bool ok;
  final String? body;

  FetchResponse({
    required this.status,
    required this.ok,
    required this.body,
  });
}
