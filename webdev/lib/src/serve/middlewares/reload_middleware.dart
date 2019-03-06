// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../injected/configuration.dart';

/// File extension that build_web_compilers will place the
/// [entrypointExtensionMarker] in.
const bootstrapJsExtension = '.bootstrap.js';

/// Marker placed by build_web_compilers for where to put injected JS code.
const entrypointExtensionMarker = '/* ENTRYPOINT_EXTENTION_MARKER */';

const _clientScript = 'webdev/src/serve/injected/client';

Handler Function(Handler) createReloadHandler(
        ReloadConfiguration configuration) =>
    (innerHandler) {
      return (Request request) async {
        if (request.url.path == '$_clientScript.js') {
          var uri = await Isolate.resolvePackageUri(
              Uri.parse('package:$_clientScript.js'));
          var result = await File(uri.toFilePath()).readAsString();
          return Response.ok(result, headers: {
            HttpHeaders.contentTypeHeader: 'application/javascript'
          });
        } else if (request.url.path.endsWith(bootstrapJsExtension)) {
          var ifNoneMatch = request.headers[HttpHeaders.ifNoneMatchHeader];
          if (ifNoneMatch != null) {
            // Disable caching of the inner hander by manually modifying the
            // if-none-match header before forwarding the request.
            request = request.change(headers: {
              HttpHeaders.ifNoneMatchHeader: '$ifNoneMatch\$injected',
            });
          }

          var response = await innerHandler(request);
          if (response.statusCode == HttpStatus.notFound) return response;
          var body = await response.readAsString();
          var etag = response.headers[HttpHeaders.etagHeader];
          var newHeaders = Map.of(response.headers);
          if (body.startsWith(entrypointExtensionMarker)) {
            body += _injectedClientJs(configuration);

            etag = base64.encode(md5.convert(body.codeUnits).bytes);
            newHeaders[HttpHeaders.etagHeader] = etag;
          }
          if (ifNoneMatch == etag) {
            return Response.notModified(headers: newHeaders);
          }
          return response.change(body: body, headers: newHeaders);
        } else {
          return innerHandler(request);
        }
      };
    };

String _injectedClientJs(ReloadConfiguration configuration) => '''\n
// Injected by webdev for build results support.
window.\$dartReloadConfiguration = "$configuration";
window.\$dartLoader.forceLoadModule('$_clientScript');
''';
