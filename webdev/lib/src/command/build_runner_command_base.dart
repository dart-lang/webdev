// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' hide exitCode, exit;
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:stack_trace/stack_trace.dart';

import '../pubspec.dart';

const _packagesFileName = '.packages';

/// Extend to get a command with the arguments common to all build_runner
/// commands.
abstract class BuildRunnerCommandBase extends Command<int> {
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

  Future<int> runCore(String command) async {
    await checkPubspecLock();

    var buildRunnerScript = await _buildRunnerScript();

    final arguments = [command]..addAll(argResults.arguments);

    var exitCode = 0;

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

    try {
      await Isolate.spawnUri(buildRunnerScript, arguments, messagePort.sendPort,
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

      return exitCode;
    } finally {
      exitPort.close();
      errorPort.close();
      messagePort.close();
    }
  }
}

Future<Uri> _buildRunnerScript() async {
  var packagesFile = new File(_packagesFileName);
  if (!packagesFile.existsSync()) {
    throw new FileSystemException(
        'A `$_packagesFileName` file does not exist in the target directory.',
        packagesFile.absolute.path);
  }

  var dataUri = new Uri.dataFromString(_bootstrapScript);

  var messagePort = new ReceivePort();
  var exitPort = new ReceivePort();
  var errorPort = new ReceivePort();

  try {
    await Isolate.spawnUri(dataUri, [], messagePort.sendPort,
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: true,
        packageConfig: new Uri.file(_packagesFileName));

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
      throw new StateError('An error occurred while bootstrapping.');
    }

    assert(messages.length == 1);
    return new Uri.file(messages.single as String);
  } finally {
    messagePort.close();
    exitPort.close();
    errorPort.close();
  }
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
