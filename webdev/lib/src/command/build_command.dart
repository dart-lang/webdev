// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:stack_trace/stack_trace.dart';

import 'configuration.dart';
import 'shared.dart';

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
const _packagesFileName = '.packages';

Future<Uri> _buildRunnerScript() async {
  var packagesFile = File(_packagesFileName);
  if (!packagesFile.existsSync()) {
    throw FileSystemException(
        'A `$_packagesFileName` file does not exist in the target directory.',
        packagesFile.absolute.path);
  }

  var dataUri = Uri.dataFromString(_bootstrapScript);

  var messagePort = ReceivePort();
  var exitPort = ReceivePort();
  var errorPort = ReceivePort();

  try {
    await Isolate.spawnUri(dataUri, [], messagePort.sendPort,
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: true,
        packageConfig: Uri.file(_packagesFileName));

    var allErrorsFuture = errorPort.forEach((error) {
      var errorList = error as List;
      var message = errorList[0] as String;
      var stack = StackTrace.fromString(errorList[1] as String);

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
      throw StateError('An error occurred while bootstrapping.');
    }

    assert(messages.length == 1);
    return Uri.file(messages.single as String);
  } finally {
    messagePort.close();
    exitPort.close();
    errorPort.close();
  }
}

/// Command to execute pub run build_runner build.
class BuildCommand extends Command<int> {
  @override
  final argParser = ArgParser(usageLineLength: lineLength);

  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  BuildCommand() {
    addSharedArgs(argParser, outputDefault: 'web:build');
  }

  @override
  Future<int> run() {
    if (argResults.rest.isNotEmpty) {
      throw UsageException(
          'Arguments were provided that are not supported: '
          '"${argResults.rest.join(' ')}".',
          argParser.usage);
    }
    return runCore('build', extraArgs: ['--fail-on-severe']);
  }

  Future<int> runCore(String command, {List<String> extraArgs}) async {
    var configuration = await Configuration.fromArgs(argResults);
    var pubspecLock = await readPubspecLock(configuration);
    final arguments = [command]
      ..addAll(extraArgs ?? const [])
      ..addAll(buildRunnerArgs(pubspecLock, configuration));

    stdout.write('Creating build script');
    var stopwatch = Stopwatch()..start();
    var buildRunnerScript = await _buildRunnerScript();
    stdout.writeln(', took ${stopwatch.elapsedMilliseconds}ms');

    var exitCode = 0;

    // Heavily inspired by dart-lang/build @ 0c77443dd7
    // /build_runner/bin/build_runner.dart#L58-L85
    var exitPort = ReceivePort();
    var errorPort = ReceivePort();
    var messagePort = ReceivePort();
    var errorListener = errorPort.listen((e) {
      stderr.writeln('\n\nYou have hit a bug in build_runner');
      stderr.writeln('Please file an issue with reproduction steps at '
          'https://github.com/dart-lang/build/issues\n\n');
      final error = e[0];
      final trace = e[1] as String;
      stderr.writeln(error);
      stderr.writeln(Trace.parse(trace).terse);
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
          throw StateError(
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
