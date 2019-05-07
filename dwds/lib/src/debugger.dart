import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart' as source_maps;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'chrome_proxy_service.dart';
import 'helpers.dart';


/// Keeps track of the scripts (both Dart and JS) and their source maps.
class SourceMaps {

  // ### Do we need a generic class for these things, or some central way of finding the main connection?
  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  /// Dart (#### wrong, JS, fix??###) URL to script.  (the script has the JS url)
  Map<String, WipScript> jsScripts = {};

  /// JS URL to sourcemap
  Map<String, source_maps.SingleMapping> sourcemaps = {};

  StreamController<String> sourceMapLoadedController = StreamController<String>.broadcast();
  Stream<String> get sourceMapLoaded => sourceMapLoadedController.stream;

    /// Called to handle the even that a script has been parsed
  /// and add its sourcemap information.
  Future<Null> _scriptParsed(ScriptParsedEvent e) async {
    var script = e.script;
    // var source = await chromeDebugger.getScriptSource(script.scriptId);
    var sourceMapContents = await sourceMap(script);
    if (sourceMapContents == null) return;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = source_maps.parse(sourceMapContents);
    if (mapping is source_maps.SingleMapping) {
    #### Iterate the dart urls which are in the mapping and call _makeUrlAbsolute on them
      jsScripts[script.url] = script;
      sourcemaps[script.url] = mapping;
      for (var dartUrl in mapping.urls) {
        sourceMapLoadedController.add(dartUrl);
      }
    }
  }

  _makeUrlAbsolute(String mainUrl, String relativeUrl) {
     return p.join(p.dirname(mainUrl), relativeUrl);
  }

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

  /// The source map for a JS [script].
  Future<String> sourceMap(WipScript script) async {
    var sourceMapUrl = script.sourceMapURL;

    if (sourceMapUrl == null || sourceMapUrl.isEmpty) {
            return null;
    }
    var absolute = p.join(p.dirname(script.url), sourceMapUrl);
    var sourceMapContents = await fetch(absolute);
    return sourceMapContents;
  }


}


class DebuggerProxyThing {
  DebuggerProxyThing(this.mainProxy);

  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  SourceMaps sourcemaps = SourceMaps();

  Future<Null> initialize() async {
    chromeDebugger.onScriptParsed.listen(sourcemaps._scriptParsed);
    await chromeDebugger.enable();
  }

    Future<ScriptRef> _getScriptById(String isolateId, String scriptId) async {
    var scripts = await mainProxy.getScriptRefs(isolateId);
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
    Isolate isolate;
    if (isolateId != null) isolate = await mainProxy.getIsolate(isolateId);
    ScriptRef dartScript = await _getScriptById(isolateId, scriptId);
    var jsScript = jsScripts[dartScript.uri];
    var sourcemap = sourcemaps[dartScript.uri];

    var location = jsPosition(sourcemap, line);
    // actually set the breakpoint
            WipResponse result;
        try {
          result = await chromeDebugger
              .sendCommand('Debugger.setBreakpoint', params: {
            'location': {
              'scriptId': jsScript.scriptId,
              'lineNumber': location.jsLine,
            }
          });
        } catch (e) {
          // throw RpcError(102)..data.details = '$e';
          rethrow;
        }
    var jsBreakpointId = result.result['breakpointId'];
    var breakpoint = Breakpoint()
          ..resolved = true
          ..location = (SourceLocation()
            ..script = dartScript
            ..tokenPos = location.dartTokenPos);

        // _jsBreakpointIdToDartId[jsBreakpointId] = breakpoint.id;
        // _dartBreakpointIdToJsId[breakpoint.id] = jsBreakpointId;

        mainProxy.streamNotify(
            'Debug',
            Event()
              ..kind = EventKind.kBreakpointAdded
              ..isolate = toIsolateRef(isolate)
              ..breakpoint = breakpoint);
        return breakpoint;

      }

   jsPosition(source_maps.SingleMapping sourcemap, int line) {
     for (var lineEntry in sourcemap.lines) {
       for (var entry in lineEntry.entries) {
        var index = entry.sourceUrlId;
        if (index == null) continue;
        // var dartUrl = _dartifiedUrl(p.join(parent, mapping.urls[index]));
        var dartLine = entry.sourceLine;
        var dartColumn = entry.sourceColumn;
        var jsLine = lineEntry.line;
        var jsColumn = entry.column;
        var jsScriptId = 'bogus script id';
        var dartUrl = 'bogus dart url';
        if (dartLine == line) {
          return Location(jsScriptId, jsLine, jsColumn, dartUrl, dartLine, dartColumn, 0);
        }
       }
     }
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

// ### Use jsScript rather than id? Or do we not have the script?
class Location {
  Location(this.jsScriptId, this.jsLine, this.jsColumn, this.dartUrl,
      this.dartLine, this.dartColumn, this.dartTokenPos);

  final String jsScriptId;
  final int jsLine;
  final int jsColumn;
  final String dartUrl;
  final int dartLine;
  final int dartColumn;
  final int dartTokenPos;
}