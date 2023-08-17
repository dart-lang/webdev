// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The path to the package config.
String? get packageConfigPath => _packageConfigPath;
String? _packageConfigPath;
void setPackageConfigPath(path) => _packageConfigPath = path;
