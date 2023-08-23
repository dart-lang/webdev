// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/strategy.dart';

/// The load strategy for the connected app.
late LoadStrategy _globalLoadStrategy;
set globalLoadStrategy(LoadStrategy strategy) => _globalLoadStrategy = strategy;
LoadStrategy get globalLoadStrategy => _globalLoadStrategy;

/// Whether or not the connected app is an internal (e.g. google3) app.
bool get globalIsInternalBuild => _isInternalBuild ?? false;
bool? _isInternalBuild;
set globalIsInternalBuild(bool isInternalBuild) =>
    _isInternalBuild = isInternalBuild;
