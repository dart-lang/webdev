// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:async/async.dart';
import 'package:pedantic/pedantic.dart';

import '../daemon/app_domain.dart';
import '../daemon/daemon.dart';
import '../daemon/daemon_domain.dart';
import '../logging.dart';
import '../serve/dev_workflow.dart';
import '../serve/utils.dart';
import 'configuration.dart';
import 'shared.dart';

Stream<Map<String, dynamic>> get _stdinCommandStream => stdin
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .where((String line) => line.startsWith('[{') && line.endsWith('}]'))
        .map<Map<String, dynamic>>((String line) {
      line = line.substring(1, line.length - 1);
      return json.decode(line) as Map<String, dynamic>;
    });

void _stdoutCommandResponse(Map<String, dynamic> command) {
  stdout.writeln('[${json.encode(command)}]');
}

/// A mode for running WebDev from command-line tools.
///
/// Communication happens over STDIO using JSON-RPC.
///
/// This supports a subset of:
/// https://github.com/flutter/flutter/blob/master/packages/flutter_tools/doc/daemon.md
class DaemonCommand extends Command<int> {
  @override
  final name = 'daemon';

  @override
  final hidden = true;

  @override
  String get description =>
      'A mode for running WebDev from command-line tools.';

  @override
  Future<int> run() async {
    Daemon daemon;
    DevWorkflow workflow;
    var cancelCount = 0;
    var cancelSub = StreamGroup.merge(
            [ProcessSignal.sigint.watch(), ProcessSignal.sigterm.watch()])
        .listen((signal) async {
      cancelCount++;
      daemon?.shutdown();
      if (cancelCount > 1) exit(1);
    });
    try {
      daemon = Daemon(_stdinCommandStream, _stdoutCommandResponse);
      var daemonDomain = DaemonDomain(daemon);
      setLogHandler((level, message, {verbose}) {
        daemonDomain.sendEvent('daemon.log', {'log': message});
      });
      daemon.registerDomain(daemonDomain);
      var configuration =
          Configuration(launchInChrome: true, debug: true, autoRun: false);
      var pubspecLock = await readPubspecLock(configuration);
      var buildOptions = buildRunnerArgs(pubspecLock, configuration);
      var port = await findUnusedPort();
      workflow = await DevWorkflow.start(
        configuration,
        buildOptions,
        {'web': port},
      );
      daemon.registerDomain(AppDomain(daemon, workflow.serverManager));
      await daemon.onExit;
      return 0;
    } catch (e) {
      daemon?.shutdown();
      rethrow;
    } finally {
      unawaited(cancelSub.cancel());
      unawaited(workflow?.shutDown());
    }
  }
}
