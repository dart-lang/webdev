// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/version.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

/// File extension that build_web_compilers will place the
/// [entrypointExtensionMarker] in.
const bootstrapJsExtension = '.bootstrap.js';

/// Marker placed by build_web_compilers for where to put injected JS code.
const entrypointExtensionMarker = '/* ENTRYPOINT_EXTENTION_MARKER */';

/// Marker placed by build_web_compilers for where to put injected JS code.
const mainExtensionMarker = '/* MAIN_EXTENSION_MARKER */';

const _clientScript = 'dwds/src/injected/client';

/// Handles injecting the DWDS client and embedding debugging related
/// information.
class DwdsInjector {
  final Future<String>? _extensionUri;
  final _devHandlerPaths = StreamController<String>();
  final _logger = Logger('DwdsInjector');

  DwdsInjector({
    Future<String>? extensionUri,
  }) : _extensionUri = extensionUri;

  /// Returns the embedded dev handler paths.
  ///
  /// This will be next to the requested entrypoints.
  Stream<String> get devHandlerPaths => _devHandlerPaths.stream;

  Middleware get middleware => (innerHandler) {
        return (Request request) async {
          if (request.url.path.endsWith('$_clientScript.js')) {
            final uri = await Isolate.resolvePackageUri(
              Uri.parse('package:$_clientScript.js'),
            );
            if (uri == null) {
              throw StateError('Cannot resolve "package:$_clientScript.js"');
            }
            final result = await File(uri.toFilePath()).readAsString();
            return Response.ok(
              result,
              headers: {
                HttpHeaders.contentTypeHeader: 'application/javascript',
              },
            );
          } else if (request.url.path.endsWith(bootstrapJsExtension)) {
            final ifNoneMatch = request.headers[HttpHeaders.ifNoneMatchHeader];
            if (ifNoneMatch != null) {
              // Disable caching of the inner handler by manually modifying the
              // if-none-match header before forwarding the request.
              request = request.change(
                headers: {
                  HttpHeaders.ifNoneMatchHeader: '$ifNoneMatch\$injected',
                },
              );
            }
            final response = await innerHandler(request);
            if (response.statusCode == HttpStatus.notFound) return response;
            var body = await response.readAsString();
            var etag = response.headers[HttpHeaders.etagHeader];
            final newHeaders = Map.of(response.headers);
            if (body.startsWith(entrypointExtensionMarker)) {
              // The requestedUri contains the hostname and port which guarantees
              // uniqueness.
              final requestedUri = request.requestedUri;
              final appId = base64
                  .encode(md5.convert(utf8.encode('$requestedUri')).bytes);
              var scheme = request.requestedUri.scheme;
              if (!globalToolConfiguration
                  .debugSettings.useSseForInjectedClient) {
                // Switch http->ws and https->wss.
                scheme = scheme.replaceFirst('http', 'ws');
              }
              final requestedUriBase = '$scheme'
                  '://${request.requestedUri.authority}';
              var devHandlerPath = '\$dwdsSseHandler';
              final subPath = request.url.pathSegments.toList()..removeLast();
              if (subPath.isNotEmpty) {
                devHandlerPath = '${subPath.join('/')}/$devHandlerPath';
              }
              _logger.info('Received request for entrypoint at $requestedUri');
              devHandlerPath = '$requestedUriBase/$devHandlerPath';
              _devHandlerPaths.add(devHandlerPath);
              final entrypoint = request.url.path;

              // Track the main entrypoint for the app read the build metadata.
              await globalToolConfiguration.loadStrategy
                  .trackAppEntrypoint(entrypoint);

              body = _injectClientAndHoistMain(
                body,
                appId,
                devHandlerPath,
                entrypoint,
                await _extensionUri,
              );
              _logger.info('Injecting debugging metadata for '
                  'entrypoint at $requestedUri');
              body += await globalToolConfiguration.loadStrategy
                  .bootstrapFor(entrypoint);
              _logger.info('Injected debugging metadata for '
                  'entrypoint at $requestedUri');
              etag = base64.encode(md5.convert(body.codeUnits).bytes);
              newHeaders[HttpHeaders.etagHeader] = etag;
            }
            if (ifNoneMatch == etag) {
              return Response.notModified(headers: newHeaders);
            }
            return response.change(body: body, headers: newHeaders);
          } else {
            final loadResponse =
                await globalToolConfiguration.loadStrategy.handler(request);
            if (loadResponse.statusCode != HttpStatus.notFound) {
              return loadResponse;
            }
            return innerHandler(request);
          }
        };
      };
}

/// Returns the provided body with the main function hoisted into a global
/// variable and a snippet of JS that loads the injected client.
String _injectClientAndHoistMain(
  String body,
  String appId,
  String devHandlerPath,
  String entrypointPath,
  String? extensionUri,
) {
  // TODO(annagrin): google3 already sets appName in the bootstrap file, so we need
  // other build system to do the same before rolling this to google3, or figure a
  // way to set appName here only if not defined already.
  final bodyLines = body.split('\n');
  final entrypointExtensionIndex =
      bodyLines.indexWhere((line) => line.contains(entrypointExtensionMarker));
  var result = bodyLines.sublist(0, entrypointExtensionIndex).join('\n');
  result += '''
    var appName = 'TestApp';
  ''';

  final extensionIndex =
      bodyLines.indexWhere((line) => line.contains(mainExtensionMarker));
  result +=
      bodyLines.sublist(entrypointExtensionIndex, extensionIndex).join('\n');
  // The line after the marker calls `main`. We prevent `main` from
  // being called and make it runnable through a global variable.
  final mainFunction =
      bodyLines[extensionIndex + 1].replaceAll('main();', 'main').trim();
  // We inject the client in the entry point module as the client expects the
  // application to be in a ready state, that is the main function is hoisted
  // and the Dart SDK is loaded.
  final injectedClientSnippet = _injectedClientSnippet(
    appId,
    devHandlerPath,
    entrypointPath,
    extensionUri,
  );
  result += '''
  // Injected by dwds for debugging support.
  if(!window.\$dwdsInitialized) {
    window.\$dwdsInitialized = true;
    window.\$dartMainTearOffs = [$mainFunction];
    window.\$dartRunMain = function() {
      window.\$dartMainExecuted = true;
      window.\$dartMainTearOffs.forEach(function(main){
         main();
      });
    }
    $injectedClientSnippet
  } else {
    if (typeof window.\$dartRegisterEntrypoint != "undefined") {
      window.\$dartRegisterEntrypoint(
          /* app name */ appName,
          /* entrypoint */ "$entrypointPath",
      );
    } 
    if (window.\$dartMainExecuted) {
      $mainFunction();
    } else {
      window.\$dartMainTearOffs.push($mainFunction);
    }
  }
  ''';
  result += bodyLines.sublist(extensionIndex + 2).join('\n');
  return result;
}

/// JS snippet which includes global variables required for debugging.
String _injectedClientSnippet(
  String appId,
  String devHandlerPath,
  String entrypointPath,
  String? extensionUri,
) {
  final loadStrategy = globalToolConfiguration.loadStrategy;
  final buildSettings = loadStrategy.buildSettings;
  final appMetadata = globalToolConfiguration.appMetadata;
  final debugSettings = globalToolConfiguration.debugSettings;

  final appInfo = JSAppInfo(
    appId: appId,
    devHandlerPath: devHandlerPath,
    dwdsVersion: packageVersion,
    emitDebugEvents: debugSettings.emitDebugEvents,
    enableDevToolsLaunch: debugSettings.enableDevToolsLaunch,
    entrypointPath: entrypointPath,
    extensionUrl: extensionUri,
    isFlutterApp: buildSettings.isFlutterApp,
    isInternalBuild: appMetadata.isInternalBuild,
    loadModuleConfig: loadStrategy.loadModuleSnippet,
    moduleStrategy: loadStrategy.id,
    reloadConfiguration: loadStrategy.reloadConfiguration,
    workspaceName: appMetadata.workspaceName,
  );

  return '\n'
      // Used by DDC runtime to detect if a debugger is attached.
      '    window.\$dwdsVersion = "$packageVersion";\n'
      // Used by the injected client to communicate with the debugger.
      '    window.\$dartAppInfo = ${appInfo.toJs()};\n'
      // Load the injected client.
      '    ${loadStrategy.loadClientSnippet(_clientScript)};\n';
}

/// Generate JS app info object for the injected client.
/// TODO(annagrin): ensure client's AppInfo can read this object.
class JSAppInfo {
  String moduleStrategy;
  ReloadConfiguration reloadConfiguration;
  String loadModuleConfig;
  String dwdsVersion;
  bool enableDevToolsLaunch;
  bool emitDebugEvents;
  bool isInternalBuild;
  String appId;
  bool isFlutterApp;
  String? extensionUrl;
  String devHandlerPath;
  String entrypointPath;
  String? workspaceName;

  JSAppInfo({
    required this.appId,
    required this.devHandlerPath,
    required this.dwdsVersion,
    required this.emitDebugEvents,
    required this.enableDevToolsLaunch,
    required this.entrypointPath,
    required this.extensionUrl,
    required this.isFlutterApp,
    required this.isInternalBuild,
    required this.loadModuleConfig,
    required this.moduleStrategy,
    required this.reloadConfiguration,
    required this.workspaceName,
  });

  String toJs() {
    final fields = {
      'moduleStrategy': '"$moduleStrategy"',
      'reloadConfiguration': '"$reloadConfiguration"',
      'loadModuleConfig': loadModuleConfig,
      'dwdsVersion': '"$dwdsVersion"',
      'enableDevToolsLaunch': enableDevToolsLaunch,
      'emitDebugEvents': emitDebugEvents,
      'isInternalBuild': isInternalBuild,
      'appName': 'appName',
      'appId': '"$appId"',
      'isFlutterApp': isFlutterApp,
      'devHandlerPath': '"$devHandlerPath"',
      'entrypoints': '["$entrypointPath"]',
      if (extensionUrl != null) 'extensionUrl': '"$extensionUrl"',
      if (workspaceName != null) 'workspaceName': '"$workspaceName"',
    };

    final lines = fields.entries.map((e) => '  ${e.key}: ${e.value},');
    return ['{', ...lines, '}'].join('\n    ');
  }
}
