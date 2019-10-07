// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/asset_handler.dart';
import 'package:dwds/src/debugging/sources.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

void main() {
  test('Gracefully handles missing source maps', () async {
    var sourcePath = 'source.ddc.js';
    var sourceMapPath = '$sourcePath.map';
    var assets = {
      sourcePath: '',
    };
    var logs = <LogRecord>[];
    var sources = Sources(TestingAssetHandler(assets), null,
        (level, message) => logs.add(LogRecord(level, message, '')), '');
    var serverUri = 'http://localhost:1234/';
    await sources.scriptParsed(ScriptParsedEvent(WipEvent({
      'params': {
        'url': '$serverUri$sourcePath',
        'sourceMapURL': '$serverUri$sourceMapPath'
      }
    })));
    expect(
        logs,
        contains(predicate((LogRecord log) =>
            log.level >= Level.WARNING ||
            log.message
                .contains('Failed to load asset at path: $sourceMapPath'))));
  });
}

class TestingAssetHandler implements AssetHandler {
  final Map<String, String> _assets;

  @override
  Handler get handler => throw UnimplementedError();

  TestingAssetHandler(this._assets);

  @override
  Future<Response> getRelativeAsset(String path) async {
    var content = _assets[path];
    if (content == null) {
      return Response.notFound('Not found');
    }
    return Response.ok(content);
  }
}
