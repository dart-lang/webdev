// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/config/app_metadata.dart';
import 'package:dwds/src/config/debug_settings.dart';
import 'package:dwds/src/loaders/strategy.dart';

/// The load strategy for the connected app.
late LoadStrategy _globalLoadStrategy;
set globalLoadStrategy(LoadStrategy strategy) => _globalLoadStrategy = strategy;
LoadStrategy get globalLoadStrategy => _globalLoadStrategy;

/// The debug settings for the connected app.
late DebugSettings _globalDebugSettings;
set globalDebugSettings(DebugSettings settings) =>
    _globalDebugSettings = settings;
DebugSettings get globalDebugSettings => _globalDebugSettings;

/// Metadata for the connected app.
late AppMetadata _globalAppMetadata;
set globalAppMetadata(AppMetadata metadata) => _globalAppMetadata = metadata;
AppMetadata get globalAppMetadata => _globalAppMetadata;
