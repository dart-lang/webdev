// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:logging/logging.dart';

/// The tool configuration for the connected app.
///
/// TODO(elliette): Consider making this final (would require updating tests
/// that currently depend on changing the configuration between test cases).
<String, String>{} globalChromeScriptIdToUrl;