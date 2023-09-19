// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/config/app_metadata.dart';
import 'package:dwds/src/config/debug_settings.dart';
import 'package:dwds/src/loaders/strategy.dart';

class ToolConfiguration {
  LoadStrategy loadStrategy;
  DebugSettings debugSettings;
  AppMetadata appMetadata;

  ToolConfiguration({
    required this.loadStrategy,
    required this.debugSettings,
    required this.appMetadata,
  });
}

/// The tool configuration for the connected app.
late ToolConfiguration _globalToolConfiguration;
set globalToolConfiguration(ToolConfiguration configuration) =>
    _globalToolConfiguration = configuration;
ToolConfiguration get globalToolConfiguration => _globalToolConfiguration;
