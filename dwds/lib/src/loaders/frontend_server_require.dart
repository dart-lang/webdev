// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dwds/src/loaders/frontend_server_strategy_provider.dart';
import 'package:dwds/src/loaders/require.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider
    extends FrontendServerStrategyProvider<RequireStrategy> {
  late final RequireStrategy _requireStrategy = RequireStrategy(
    configuration,
    moduleProvider,
    (_) => digestsProvider(),
    moduleForServerPath,
    serverPathForModule,
    sourceMapPathForModule,
    serverPathForAppUri,
    moduleInfoForProvider,
    assetReader,
    buildSettings,
  );

  FrontendServerRequireStrategyProvider(
    super.configuration,
    super.assetReader,
    super.packageUriMapper,
    super.digestsProvider,
    super.buildSettings,
  );

  @override
  RequireStrategy get strategy => _requireStrategy;
}
