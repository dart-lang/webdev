// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:logging/logging.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_packages_handler/shelf_packages_handler.dart';
import 'package:shelf_static/shelf_static.dart';

import 'asset_reader.dart';

/// A reader for Dart sources and related source maps provided by the Frontend
/// Server.
class FrontendServerAssetReader implements AssetReader {
  final File _mapOriginal;
  final File _mapIncremental;
  final File _jsonOriginal;
  final File _jsonIncremental;
  final LogWriter _logWriter;

  /// Handler for Dart resources.
  final _sourceHandler = Completer<Handler>();

  /// Map of Dart module server path to source map contents.
  final _mapContents = <String, String>{};

  bool _haveReadOriginals = false;

  /// Creates a [FrontendServerAssetReader].
  ///
  /// [outputPath] is the file path to the Frontend Server kernel file e.g.
  ///
  ///   /some/path/main.dart.dill
  ///
  /// Corresponding `.json` and `.map` files will be read relative to
  /// [outputPath].
  ///
  /// [packageRoot] is the path to the directory that contains a `.packages`
  /// file for the application.
  FrontendServerAssetReader(
    String outputPath,
    String packageRoot,
    this._logWriter,
  )   : _mapOriginal = File('$outputPath.map'),
        _mapIncremental = File('$outputPath.incremental.map'),
        _jsonOriginal = File('$outputPath.json'),
        _jsonIncremental = File('$outputPath.incremental.json') {
    () async {
      var cascade = Cascade()
          .add(packagesDirHandler(
              resolver: await PackageResolver.loadConfig(
                  p.toUri(p.join(packageRoot, '.packages')))))
          .add(createStaticHandler(packageRoot));
      _sourceHandler.complete(cascade.handler);
    }();
  }

  @override
  Future<String> dartSourceContents(String serverPath) async {
    if (!serverPath.endsWith('.dart')) return null;
    var sourceHandler = await _sourceHandler.future;

    // We need a valid HTTP URI for the handler to properly resolve resources.
    // The host and port don't actually matter though.
    var response = await sourceHandler(
        Request('GET', Uri.parse('http://localhost:8080/$serverPath')));

    if (response.statusCode != HttpStatus.ok) {
      _logWriter(Level.WARNING, '''
      Failed to load asset at path: $serverPath.

      Status code: ${response.statusCode}

      Headers:
      ${const JsonEncoder.withIndent('  ').convert(response.headers)}
      ''');
      return null;
    } else {
      return await response.readAsString();
    }
  }

  @override
  Future<String> sourceMapContents(String serverPath) async {
    if (!serverPath.endsWith('lib.js.map')) return null;
    if (!serverPath.startsWith('/')) serverPath = '/$serverPath';
    // Strip the .map, sources are looked up by their js path.
    return _mapContents[p.withoutExtension(serverPath)];
  }

  /// Updates the internal caches by reading the Frontend Server output files.
  ///
  /// Will only read the incremental files on additional calls.
  Future<void> updateCaches() async {
    if (!_haveReadOriginals) {
      await _updateCaches(_mapOriginal, _jsonOriginal);
      _haveReadOriginals = true;
    } else {
      await _updateCaches(_mapIncremental, _jsonIncremental);
    }
  }

  Future<void> _updateCaches(File map, File json) async {
    if (!(await map.exists() && await json.exists())) {
      throw StateError('$map and $json do not exist.');
    }
    var sourceContents = await map.readAsBytes();
    var sourceInfo =
        jsonDecode(await json.readAsString()) as Map<String, dynamic>;
    for (var key in sourceInfo.keys) {
      var info = sourceInfo[key];
      _mapContents[key] = utf8.decode(sourceContents
          .getRange(
            info['sourcemap'][0] as int,
            info['sourcemap'][1] as int,
          )
          .toList());
    }
  }
}
