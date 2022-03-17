// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dwds/dwds.dart';
import 'package:file/file.dart' hide Directory;
import 'package:logging/logging.dart';
import 'package:mime/mime.dart' as mime;
import 'package:package_config/package_config.dart'; // ignore: deprecated_member_use
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

import 'utilities.dart';

Logger _logger = Logger('TestAssetServer');

class TestAssetServer implements AssetReader {
  TestAssetServer(
    this._root,
    this._httpServer,
    this._packages,
    this.internetAddress,
    this._fileSystem,
  );

  // Fallback to "application/octet-stream" on null which
  // makes no claims as to the structure of the data.
  static const String _defaultMimeType = 'application/octet-stream';
  final FileSystem _fileSystem;

  /// Start the web asset server on a [hostname] and [port].
  ///
  /// Unhandled exceptions will throw a exception with the error and stack
  /// trace.
  static Future<TestAssetServer> start(
    FileSystem fileSystem,
    String root,
    String hostname,
    int port,
    UrlEncoder urlTunneller,
  ) async {
    var address = (await InternetAddress.lookup(hostname)).first;
    var httpServer = await HttpServer.bind(address, port);
    print('ROOT IS $root');
    print('URI IS ${Uri.base}');
    // var packages = await findPackageConfig(Directory.fromUri(Uri.base));
    var packages = await loadPackageConfigUri(
        Uri.base.resolve('package_config.json'),
        loader: (Uri uri) => fileSystem.file(uri).readAsBytes());
    print('======== PACKAGE VERSION IS ${packages.version}');
    var server =
        TestAssetServer(root, httpServer, packages, address, fileSystem);

    return server;
  }

  final String _root;
  final HttpServer _httpServer;
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Map<String, Uint8List> _sourcemaps = <String, Uint8List>{};
  final Map<String, Uint8List> _metadata = <String, Uint8List>{};
  String _mergedMetadata;
  // ignore: deprecated_member_use
  final PackageConfig _packages;
  final InternetAddress internetAddress;

  Uint8List getFile(String path) => _files[path];

  Uint8List getSourceMap(String path) => _sourcemaps[path];

  // handle requests for JavaScript source, dart sources maps, or asset files.
  Future<shelf.Response> handleRequest(shelf.Request request) async {
    var headers = <String, String>{};

    // Index file is serverd from the _root directory
    if (request.url.path.endsWith('index.html')) {
      final indexFile = _fileSystem.currentDirectory
          .childDirectory(_root)
          .childFile('index.html');
      if (indexFile.existsSync()) {
        headers[HttpHeaders.contentTypeHeader] = 'text/html';
        headers[HttpHeaders.contentLengthHeader] =
            indexFile.lengthSync().toString();
        return shelf.Response.ok(indexFile.openRead(), headers: headers);
      }
      return shelf.Response.notFound('');
    }

    // NOTE: shelf removes leading `/` for some reason.
    var requestPath = request.url.path.startsWith('/')
        ? request.url.path
        : '/${request.url.path}';

    // If this is a JavaScript file, it must be in the in-memory cache.
    // Attempt to look up the file by URI.
    if (_files.containsKey(requestPath)) {
      final List<int> bytes = getFile(requestPath);
      headers[HttpHeaders.contentLengthHeader] = bytes.length.toString();
      headers[HttpHeaders.contentTypeHeader] = 'application/javascript';
      return shelf.Response.ok(bytes, headers: headers);
    }
    // If this is a sourcemap file, then it might be in the in-memory cache.
    // Attempt to lookup the file by URI.
    if (_sourcemaps.containsKey(requestPath)) {
      final List<int> bytes = getSourceMap(requestPath);
      headers[HttpHeaders.contentLengthHeader] = bytes.length.toString();
      headers[HttpHeaders.contentTypeHeader] = 'application/json';
      return shelf.Response.ok(bytes, headers: headers);
    }

    var file = _resolveDartFile(requestPath);
    if (!file.existsSync()) {
      return shelf.Response.notFound('');
    }

    var length = file.lengthSync();
    // Attempt to determine the file's mime type. if this is not provided some
    // browsers will refuse to render images/show video et cetera. If the tool
    // cannot determine a mime type, fall back to application/octet-stream.
    String mimeType;
    if (length >= 12) {
      mimeType = mime.lookupMimeType(
        file.path,
        headerBytes: await file.openRead(0, 12).first,
      );
    }
    mimeType ??= _defaultMimeType;
    headers[HttpHeaders.contentLengthHeader] = length.toString();
    headers[HttpHeaders.contentTypeHeader] = mimeType;
    return shelf.Response.ok(file.openRead(), headers: headers);
  }

  /// Tear down the http server running.
  @override
  Future<void> close() {
    return _httpServer.close();
  }

  /// Write a single file into the in-memory cache.
  void writeFile(String filePath, String contents) {
    _files[filePath] = Uint8List.fromList(utf8.encode(contents));
  }

  /// Update the in-memory asset server with the provided source and manifest files.
  ///
  /// Returns a list of updated modules.
  List<String> write(
      File codeFile, File manifestFile, File sourcemapFile, File metadataFile) {
    var modules = <String>[];
    var codeBytes = codeFile.readAsBytesSync();
    var sourcemapBytes = sourcemapFile.readAsBytesSync();
    var metadataBytes = metadataFile.readAsBytesSync();
    var manifest =
        castStringKeyedMap(json.decode(manifestFile.readAsStringSync()));
    for (var filePath in manifest.keys) {
      if (filePath == null) {
        _logger.severe('Invalid manfiest file: $filePath');
        continue;
      }
      var offsets = castStringKeyedMap(manifest[filePath]);
      var codeOffsets = (offsets['code'] as List<dynamic>).cast<int>();
      var sourcemapOffsets =
          (offsets['sourcemap'] as List<dynamic>).cast<int>();
      var metadataOffsets = (offsets['metadata'] as List<dynamic>).cast<int>();
      if (codeOffsets.length != 2 ||
          sourcemapOffsets.length != 2 ||
          metadataOffsets.length != 2) {
        _logger.severe('Invalid manifest byte offsets: $offsets');
        continue;
      }

      var codeStart = codeOffsets[0];
      var codeEnd = codeOffsets[1];
      if (codeStart < 0 || codeEnd > codeBytes.lengthInBytes) {
        _logger.severe('Invalid byte index: [$codeStart, $codeEnd]');
        continue;
      }
      var byteView = Uint8List.view(
        codeBytes.buffer,
        codeStart,
        codeEnd - codeStart,
      );
      _files[filePath] = byteView;

      var sourcemapStart = sourcemapOffsets[0];
      var sourcemapEnd = sourcemapOffsets[1];
      if (sourcemapStart < 0 || sourcemapEnd > sourcemapBytes.lengthInBytes) {
        _logger.severe('Invalid byte index: [$sourcemapStart, $sourcemapEnd]');
        continue;
      }
      var sourcemapView = Uint8List.view(
        sourcemapBytes.buffer,
        sourcemapStart,
        sourcemapEnd - sourcemapStart,
      );
      _sourcemaps['$filePath.map'] = sourcemapView;

      var metadataStart = metadataOffsets[0];
      var metadataEnd = metadataOffsets[1];
      if (metadataStart < 0 || metadataEnd > metadataBytes.lengthInBytes) {
        _logger.severe('Invalid byte index: [$metadataStart, $metadataEnd]');
        continue;
      }
      var metadataView = Uint8List.view(
        metadataBytes.buffer,
        metadataStart,
        metadataEnd - metadataStart,
      );
      _metadata['$filePath.metadata'] = metadataView;

      modules.add(filePath);
    }

    _mergedMetadata = _metadata.values
        .map((Uint8List encoded) => utf8.decode(encoded))
        .join('\n');

    return modules;
  }

  // Attempt to resolve `path` to a dart file.
  File _resolveDartFile(String path) {
    // If this is a dart file, it must be on the local file system and is
    // likely coming from a source map request. The tool doesn't currently
    // consider the case of Dart files as assets.
    var dartFile =
        _fileSystem.file(_fileSystem.currentDirectory.uri.resolve(path));
    if (dartFile.existsSync()) {
      return dartFile;
    }

    var segments = p.split(path);
    if (segments.first.isEmpty) {
      segments.removeAt(0);
    }

    // The file might have been a package file which is signaled by a
    // `/packages/<package>/<path>` request.
    if (segments.first == 'packages') {
      var packageFile = _fileSystem.file(_packages
          .resolve(Uri(scheme: 'package', pathSegments: segments.skip(1))));
      if (packageFile.existsSync()) {
        return packageFile;
      }
    }

    // Otherwise it must be a Dart SDK source.
    var dartSdkParent = _fileSystem.directory(dartSdkPath).parent;
    var dartSdkFile = _fileSystem.file(
        _fileSystem.path.joinAll(<String>[dartSdkParent.path, ...segments]));
    return dartSdkFile;
  }

  @override
  Future<String> dartSourceContents(String serverPath) {
    var result = _resolveDartFile(serverPath);
    if (result.existsSync()) {
      return result.readAsString();
    }
    return null;
  }

  @override
  Future<String> sourceMapContents(String serverPath) async {
    var path = '/$serverPath';
    if (_sourcemaps.containsKey(path)) {
      return utf8.decode(_sourcemaps[path]);
    }
    return null;
  }

  @override
  Future<String> metadataContents(String serverPath) async {
    if (serverPath.endsWith('.ddc_merged_metadata')) {
      return _mergedMetadata;
    }
    var path = '/$serverPath';
    if (_metadata.containsKey(path)) {
      return utf8.decode(_metadata[path]);
    }
    return null;
  }
}

/// Given a data structure which is a Map of String to dynamic values, return
/// the same structure (`Map<String, dynamic>`) with the correct runtime types.
Map<String, dynamic> castStringKeyedMap(dynamic untyped) {
  var map = untyped as Map<dynamic, dynamic>;
  return map?.cast<String, dynamic>();
}
