// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;

/// The path to the package config.
String get packageConfigPath => _packageConfigPath ?? _defaultPackageConfigPath;
String? _packageConfigPath;
void setPackageConfigPath(path) => _packageConfigPath = path;

/// The default package config path, if none is provided by the load strategy.
String get _defaultPackageConfigPath => p.join(
      DartUri.currentDirectory,
      '.dart_tool/package_config.json',
    );
