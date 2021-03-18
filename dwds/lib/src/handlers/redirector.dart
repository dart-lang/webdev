// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';

import 'package:shelf/shelf.dart';

FutureOr<Response> redirectHandler(Request request) {
  // VS Code's URI class incorrectly encodes values in URLs so we need
  // to handle values that are over-encoded, such as:
  // http://127.0.0.1:50308/%24redir?url%3Dhttp%253A%252F%252Flocalhost%253A50306

  final isRedirectRequest =
      request.url.path == r'$redir' || request.url.path == r'%24redir';

  if (isRedirectRequest && request.url.queryParameters.containsKey('url')) {
    final potentiallyEncodedUrl = request.url.queryParameters['url'];
    final url = Uri.decodeQueryComponent(potentiallyEncodedUrl);
    return Response.found(url);
  }
  return null;
}
