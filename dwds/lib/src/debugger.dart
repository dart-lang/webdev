// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:source_maps/source_maps.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'token_position.dart';

class Debugger {
  Debugger(this.mainProxy);

  final _sourceToTokens = <String, Set<TokenPos>>{};

  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  Future<Null> initialize() async {
    chromeDebugger.onScriptParsed.listen(scriptHandler);
    await chromeDebugger.enable();
  }

  // TODO(grouma) - remove this logic once alanknight@ lands the proper
  // script abstraction.
  void scriptHandler(ScriptParsedEvent event) async {
    var sourceMapUrl = event.script.sourceMapURL;
    if (sourceMapUrl != null && sourceMapUrl.isNotEmpty) {
      var contents = await mainProxy.assetHandler(sourceMapUrl);
      if (contents != 'Not Found') {
        var mapping = parse(contents);
        if (mapping is SingleMapping) {
          for (var lineEntry in mapping.lines) {
            for (var entry in lineEntry.entries) {
              var index = entry.sourceUrlId;
              if (index == null) continue;
              var dartUrl = mapping.urls[index];
              var dartLine = entry.sourceLine;
              var dartColumn = entry.sourceColumn;
              var token = TokenPos(dartLine, dartColumn);
              _sourceToTokens.putIfAbsent(dartUrl, () => Set()).add(token);
            }
          }
        }
      }
    }
  }

  List<List<int>> tokenPosTableFor(String scriptPath) {
    var tokenPosTable = <List<int>>[];
    if (!scriptPath.startsWith('/')) scriptPath = '/$scriptPath';
    var tokens = _sourceToTokens[scriptPath];
    var lineToTokens = <int, Set<TokenPos>>{};
    for (var token in tokens) {
      lineToTokens.putIfAbsent(token.line, () => {}).add(token);
    }
    for (var line in lineToTokens.keys) {
      var tokenPos = [line];
      for (var token in lineToTokens[line]) {
        tokenPos.addAll([token.id, token.column]);
      }
      tokenPosTable.add(tokenPos);
    }
    return tokenPosTable;
  }

  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    throw UnimplementedError();
  }
}
