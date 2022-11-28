// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';

import 'package:js/js.dart';
import 'dart:js_util' as js_util;

@JS()
external Console get console;

@JS()
// ignore: non_constant_identifier_names
external Json get JSON;

@JS()
@anonymous
class Console {
  external void log(String header,
      [String style1, String style2, String style3]);

  external void warn(String header,
      [String style1, String style2, String style3]);

  external void error(String header,
      [String style1, String style2, String style3]);
}

@JS()
@anonymous
class Json {
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify
  external String stringify(o);
}

// Custom implementation of Fetch API until the Dart implementation supports
// credentials. See https://github.com/dart-lang/http/issues/595.
@JS('fetch')
external Object _nativeJsFetch(String resourceUrl, FetchOptions options);

Future<FetchResponse> fetchRequest(String resourceUrl) async {
  try {
    final options = FetchOptions(
      method: 'GET',
      credentialsOptions: CredentialsOptions(credentials: 'include'),
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

@JS()
@anonymous
class FetchOptions {
  external factory FetchOptions({
    required String method, // e.g., 'GET', 'POST'
    required CredentialsOptions credentialsOptions,
  });
}

@JS()
@anonymous
class CredentialsOptions {
  external factory CredentialsOptions({
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
