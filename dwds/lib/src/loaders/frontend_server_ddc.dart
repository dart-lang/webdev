// Copyright 2023 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dwds/src/loaders/ddc.dart';
import 'package:dwds/src/loaders/frontend_server_strategy_provider.dart';

/// Provides a [DdcStrategy] suitable for use with Frontend Server.
class FrontendServerDdcStrategyProvider
    extends FrontendServerStrategyProvider<DdcStrategy> {
  FrontendServerDdcStrategyProvider(
    super.configuration,
    super.assetReader,
    super.packageUriMapper,
    super.digestsProvider,
    super.buildSettings,
  );

  @override
  DdcStrategy get strategy => DdcStrategy(
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
        (String _) => null,
        null,
      );
}
