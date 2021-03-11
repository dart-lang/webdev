// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

// Note: this is a copy from flutter tools

// TODO(annagrin): unify this code so both repos can use it
// [issue #40835] (https://github.com/dart-lang/sdk/issues/40835)

import 'dart:io';

// ignore: deprecated_member_use
import 'package:package_config/packages_file.dart' as packages_file;

import 'utilities.dart';

const String kPackagesFileName = '.packages';

Map<String, Uri> _parse(String packagesPath) {
  final List<int> source = fileSystem.file(packagesPath).readAsBytesSync();
  return packages_file.parse(
      source, Uri.file(packagesPath, windows: Platform.isWindows));
}

class PackageMap {
  PackageMap(this.packagesPath);

  static String get globalPackagesPath =>
      _globalPackagesPath ?? kPackagesFileName;

  static set globalPackagesPath(String value) {
    _globalPackagesPath = value;
  }

  static bool get isUsingCustomPackagesPath => _globalPackagesPath != null;

  static String _globalPackagesPath;

  final String packagesPath;

  /// Load and parses the .packages file.
  void load() {
    _map ??= _parse(packagesPath);
  }

  Map<String, Uri> get map {
    load();
    return _map;
  }

  Map<String, Uri> _map;

  /// Returns the path to [packageUri].
  String pathForPackage(Uri packageUri) => uriForPackage(packageUri).path;

  /// Returns the path to [packageUri] as URL.
  Uri uriForPackage(Uri packageUri) {
    assert(packageUri.scheme == 'package');
    var pathSegments = packageUri.pathSegments.toList();
    var packageName = pathSegments.removeAt(0);
    var packageBase = map[packageName];
    if (packageBase == null) {
      return null;
    }
    var packageRelativePath = fileSystem.path.joinAll(pathSegments);
    return packageBase.resolveUri(fileSystem.path.toUri(packageRelativePath));
  }

  String checkValid() {
    if (fileSystem.isFileSync(packagesPath)) {
      return null;
    }
    var message = '$packagesPath does not exist.';
    var pubspecPath = fileSystem.path
        .absolute(fileSystem.path.dirname(packagesPath), 'pubspec.yaml');
    if (fileSystem.isFileSync(pubspecPath)) {
      message += '\nDid you run "flutter pub get" in this directory?';
    } else {
      message +=
          '\nDid you run this command from the same directory as your pubspec.yaml file?';
    }
    return message;
  }
}
