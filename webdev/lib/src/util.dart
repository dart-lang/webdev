// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

final supportedBuildRunnerVersionRange = new VersionRange(
    min: new Version(0, 8, 0),
    includeMin: true,
    max: new Version(0, 9, 0),
    includeMax: false);
