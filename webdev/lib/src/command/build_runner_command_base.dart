// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:stack_trace/stack_trace.dart';

/// Extend to get a command with the arguments common to all build_runner
/// commands.
abstract class BuildRunnerCommandBase extends Command {
  BuildRunnerCommandBase() {
    // TODO(nshahan) Expose more common args passed to build_runner commands.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addOption('output',
          abbr: 'o', help: 'A directory to write the result of a build to.')
      ..addFlag('verbose',
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Enables verbose logging.');
  }

  Future runCore(String command) async {
    final arguments = [command]..addAll(argResults.arguments);

    // Heavily inspired by dart-lang/build @ 0c77443dd7
    // /build_runner/bin/build_runner.dart#L58-L85
    var exitPort = new ReceivePort();
    var errorPort = new ReceivePort();
    var messagePort = new ReceivePort();
    var errorListener = errorPort.listen((e) {
      stderr.writeln('\n\nYou have hit a bug in build_runner');
      stderr.writeln('Please file an issue with reproduction steps at '
          'https://github.com/dart-lang/build/issues\n\n');
      final error = e[0];
      final trace = e[1] as String;
      stderr.writeln(error);
      stderr.writeln(new Trace.parse(trace).terse);
      if (exitCode == 0) exitCode = 1;
    });
    await Isolate.spawnUri(
        await _buildRunnerScript(), arguments, messagePort.sendPort,
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        automaticPackageResolution: true);
    StreamSubscription exitCodeListener;
    exitCodeListener = messagePort.listen((isolateExitCode) {
      if (isolateExitCode is! int) {
        throw new StateError(
            'Bad response from isolate, expected an exit code but got '
            '$isolateExitCode');
      }
      exitCode = isolateExitCode as int;
      exitCodeListener.cancel();
      exitCodeListener = null;
    });
    await exitPort.first;
    await errorListener.cancel();
    await exitCodeListener?.cancel();
  }
}

Future<Uri> _buildRunnerScript() async {
  var dataUri = new Uri.dataFromString(_bootstrapScript);

  var messagePort = new ReceivePort();
  var exitPort = new ReceivePort();
  var errorPort = new ReceivePort();

  await Isolate.spawnUri(dataUri, [], messagePort.sendPort,
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
      packageConfig: new Uri.file('.packages'));

  var allErrorsFuture = errorPort.forEach((error) {
    var errorList = error as List;
    var message = errorList[0] as String;
    var stack = new StackTrace.fromString(errorList[1] as String);

    stderr.writeln(message);
    stderr.writeln(stack);
  });

  var items = await Future.wait([
    messagePort.toList(),
    allErrorsFuture,
    exitPort.first.whenComplete(() {
      messagePort.close();
      errorPort.close();
    })
  ]);

  var messages = items[0] as List;
  if (messages.isEmpty) {
    throw new StateError('An error occurred while running booting.');
  }

  assert(messages.length == 1);
  return new Uri.file(messages.single as String);
}

const _bootstrapScript = r'''
import 'dart:io';
import 'dart:isolate';

import 'package:build_runner/build_script_generate.dart';
import 'package:path/path.dart' as p;

void main(List<String> args, [SendPort sendPort]) async {
  var buildScript = await generateBuildScript();
  var scriptFile = new File(scriptLocation)..createSync(recursive: true);
  scriptFile.writeAsStringSync(buildScript);
  sendPort.send(p.absolute(scriptLocation));  
}
''';
