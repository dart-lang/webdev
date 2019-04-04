import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart' as sourcemaps;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'chrome_proxy_service.dart';

class DebuggerProxyThing {
  DebuggerProxyThing(this.mainProxy);

  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  Map<String, WipScript> urlToScript = {};

  Future<Null> initialize() async {
    await chromeDebugger.enable();
    chromeDebugger.onScriptParsed.listen(_scriptParsed);
  }

  Future<String> sourceMap(WipScript script) async {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null || sourceMapUrl.isEmpty) return null;
    var absolute = p.join(p.dirname(script.url), sourceMapUrl);
    var sourceMapContents = await fetch(absolute);
    return sourceMapContents;
  }

  Future<Null> _scriptParsed(ScriptParsedEvent e) async {
     var script = e.script;
    var sourceMapContents = await sourceMap(script);
    if (sourceMapContents == null) return;
        // This happens to be a [SingleMapping] today in DDC.
        var mapping = sourcemaps.parse(sourceMapContents);
        if (mapping is sourcemaps.SingleMapping) {
          urlToScript[script.url] = script;
        }



// ### Is this stuff necessary here, or is it covered by the getSourceReport api?
    //       var locationData = DartLocationData(jsUrl, jsId, mapping);
    //       _jsIdToLocationData[jsId] = locationData;

    //       for (var src in mapping.urls) {
    //         // TODO(vsm): Support part files.
    //         var dartUrl = p.join(p.dirname(jsUrl), src);
    //         // TODO(vsm): Record this properly.
    //         var dartSource = await _fetch(dartUrl);
    //         if (dartSource == null) continue;
    //         dartUrl = _dartifiedUrl(dartUrl);

    //         var dartScript = _createScript()
    //           ..uri = dartUrl
    //           ..tokenPosTable = locationData.dartUrlToTokenPosTable[dartUrl]
    //           ..source = dartSource;
    //         _dartIdToJsId[dartScript.id] = jsId;
    //         _dartUrlToScript[dartUrl] = dartScript;
    //         var library = _createLibrary()
    //           ..uri = dartUrl
    //           ..getScripts().add(dartScript)
    // #### I think the libraries are already getting created? So this is unnecessary?
    //           ..name = p.basenameWithoutExtension(dartUrl);
    //         // TODO(vsm): Need a robust way to query for the root library.
    //         if (libraries.isEmpty) isolate.rootLib = library.toRef();
    //         libraries.add(library);
    //       }
    //     }
    //     _mappings.add(mapping);
    //   }
    // }
  }

  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) await mainProxy.getIsolate(isolateId);
    return null;

    // var jsId = _dartIdToJsId[script.id];
    // var locations = _jsIdToLocationData[jsId];
    // var locationData = locations.dartLocations[script.uri];

    // for (var location in locationData) {
    //   // Match first line hit for now.
    //   if (location.dartLine >= line) {
    //     WipResponse result;
    //     try {
    //       result = await _cdp.debugger
    //           .sendCommand('Debugger.setBreakpoint', params: {
    //         'location': {
    //           'scriptId': jsId,
    //           'lineNumber': location.jsLine - 1,
    //         }
    //       });
    //     } catch (e) {
    //       throw RpcError(102)..data.details = '$e';
    //     }

    //     var jsBreakpointId = result.result['breakpointId'];
    //     // TODO(vsm):
    //     // (1) Validate that the breakpoint was resolved.
    //     // (2) Update the location to the actual location (in result.result).

    //     var breakpoint = _createBreakpoint()
    //       ..resolved = true
    //       ..location = (SourceLocation()
    //         ..script = script
    //         ..tokenPos = location.dartTokenPos);

    //     _jsBreakpointIdToDartId[jsBreakpointId] = breakpoint.id;
    //     _dartBreakpointIdToJsId[breakpoint.id] = jsBreakpointId;

    //     _streamNotify(
    //         'Debug',
    //         Event()
    //           ..kind = EventKind.BreakpointAdded
    //           ..isolate = isolate.toRef()
    //           ..breakpoint = breakpoint);
    //     return breakpoint;
    //   }

    // throw UnimplementedError();
  }
}

Future<String> fetch(String uri) async {
  try {
    if (uri.startsWith('file://')) {
      uri = uri.substring('file://'.length);
      return await File(uri).readAsString();
    } else {
      var request = await HttpClient().postUrl(Uri.parse(uri));
      request.persistentConnection = false; // Use non-persistent connection.
      var response = await request.close();
      return response.statusCode != HttpStatus.notFound
          ? response.transform(utf8.decoder).join()
          : null;
    }
  } catch (e) {
    return null;
  }
}
