// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'package:shelf/shelf.dart';

final injectLiveReloadClientCode =
    _injectBuildResultsClientCode('live_reload_client');

const clientPrefix = 'webdev/src/serve/reload_client/';
const entrypointExtensionMarker = '/* ENTRYPOINT_EXTENTION_MARKER */';

String _buildResultsInjectedJS(String scriptName) => '''\n
// Injected by webdev for build results support.
window.\$dartLoader.forceLoadModule('$clientPrefix/$scriptName');
''';

Handler Function(Handler) _injectBuildResultsClientCode(String scriptName) =>
    (innerHandler) {
      return (Request request) async {
        if (!request.url.path.endsWith('.js')) {
          return innerHandler(request);
        }
        if (request.url.path == '$clientPrefix/$scriptName.js') {
          var uri = await Isolate.resolvePackageUri(
              Uri.parse('package:$clientPrefix/$scriptName.js'));
          var result = await File(uri.toFilePath()).readAsString();
          return Response.ok(result, headers: {
            HttpHeaders.contentTypeHeader: 'application/javascript'
          });
        }
        var response = await innerHandler(request);
        var body = await response.readAsString();
        if (body.startsWith(entrypointExtensionMarker)) {
          body += _buildResultsInjectedJS(scriptName);
          var originalEtag = response.headers[HttpHeaders.etagHeader];
          if (originalEtag != null) {
            var newEtag = base64.encode(md5.convert(body.codeUnits).bytes);
            var newHeaders = Map.of(response.headers);
            newHeaders[HttpHeaders.etagHeader] = newEtag;
            if (request.headers[HttpHeaders.ifNoneMatchHeader] == newEtag) {
              return Response.notModified(headers: newHeaders);
            }
            response = response.change(headers: newHeaders);
          }
        }
        return response.change(body: body);
      };
    };
