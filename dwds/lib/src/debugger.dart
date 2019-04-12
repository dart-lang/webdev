import 'dart:async';
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

  /// Dart URL to script.  (the script has the JS url)
  Map<String, WipScript> jsScripts = {};
  /// JS URL to sourcemap
  Map<String, sourcemaps.SingleMapping> mappings = {};

  Future<Null> initialize() async {
    chromeDebugger.onScriptParsed.listen(_scriptParsed);
    await chromeDebugger.enable();

  }

  StreamController<String> sourceMapLoadedController = StreamController<String>();
  Stream<String> get sourceMapLoaded => sourceMapLoadedController.stream;

  /// Return a Future that completers once the source map for [url]
  /// has been loaded.
  Future<String> waitForSourceMap(String url) {
    var completer = Completer<String>();
    StreamSubscription listener;
    listener = sourceMapLoaded.listen((loadedUrl) {
      if (url == loadedUrl) completer.complete(url);
      listener.cancel();
    });
    return completer.future;
  }

  Future<String> sourceMap(WipScript script) async {
    var sourceMapUrl = script.sourceMapURL;

    if (sourceMapUrl == null || sourceMapUrl.isEmpty) {
            return null;
    }
    var absolute = p.join(p.dirname(script.url), sourceMapUrl);
    var sourceMapContents = await fetch(absolute);
    return sourceMapContents;
  }

  Future<Null> _scriptParsed(ScriptParsedEvent e) async {
    var script = e.script;
    // var source = await chromeDebugger.getScriptSource(script.scriptId);
    var sourceMapContents = await sourceMap(script);
    if (sourceMapContents == null) return;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = sourcemaps.parse(sourceMapContents);
    if (mapping is sourcemaps.SingleMapping) {
      jsScripts[script.url] = script;
      mappings[script.url] = mapping;
      for (var dartUrl in mapping.urls) {
        sourceMapLoadedController.add(dartUrl);
      }
    }
  }

    ScriptRef _getScriptById(String isolateId, String scriptId) {
    var scripts = _getScripts(isolateId);
    for (var script in scripts) {
      if (script.id == scriptId) {
        return script;
      }
    }
    return null;
  }

  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) await mainProxy.getIsolate(isolateId);
    var script = _getScriptById(isolateId, scriptId);
    var jsScript = jsScripts[scriptId];

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
