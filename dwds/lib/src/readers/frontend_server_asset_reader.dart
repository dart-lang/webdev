// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../../dwds.dart';
import 'asset_reader.dart';

/// A reader for Dart sources and related source maps provided by the Frontend
/// Server.
class FrontendServerAssetReader implements AssetReader {
  final File _mapOriginal;
  final File _mapIncremental;
  final File _jsonOriginal;
  final File _jsonIncremental;
  final String _packageRoot;
  final Future<PackageConfig> _packageConfig;

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
  /// [_packageRoot] is the path to the directory that contains a `.packages`
  /// file for the application.
  FrontendServerAssetReader(
    String outputPath,
    this._packageRoot,
  )   : _mapOriginal = File('$outputPath.map'),
        _mapIncremental = File('$outputPath.incremental.map'),
        _jsonOriginal = File('$outputPath.json'),
        _jsonIncremental = File('$outputPath.incremental.json'),
        _packageConfig =
            loadPackageConfig(File(p.absolute(p.join(_packageRoot, '.packages'))));

  @override
  Future<String> dartSourceContents(String serverPath) async {
    if (!serverPath.endsWith('.dart')) return null;
    var packageConfig = await _packageConfig;

    Uri fileUri;
    if (serverPath.startsWith('packages/')) {
      var packagePath = serverPath.replaceFirst('packages/', 'package:');
      fileUri = packageConfig.resolve(Uri.parse(packagePath));
    } else {
      fileUri = p.toUri(p.join(_packageRoot, serverPath));
    }

    var source = File(fileUri.toFilePath());
    if (!await source.exists()) return null;
    return await source.readAsString();
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
