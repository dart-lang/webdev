// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' hide exitCode, exit;
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';

import '../pubspec.dart';

const _packagesFileName = '.packages';
const _release = 'release';
const _output = 'output';
const _verbose = 'verbose';

const outputNone = 'NONE';

const _requireBuildWebCompilers = 'build-web-compilers';

/// Extend to get a command with the arguments common to all build_runner
/// commands.
abstract class CommandBase extends Command<int> {
  final bool releaseDefault;

  CommandBase({@required this.releaseDefault, @required String outputDefault}) {
    // TODO(nshahan) Expose more common args passed to build_runner commands.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addFlag(_release,
          abbr: 'r',
          defaultsTo: releaseDefault,
          negatable: true,
          help: 'Build with release mode defaults for builders.')
      ..addOption(
        _output,
        abbr: 'o',
        defaultsTo: outputDefault,
        help: 'A directory to write the result of a build to. Or a mapping '
            'from a top-level directory in the package to the directory to '
            'write a filtered build output to. For example "web:deploy".\n'
            'A value of "NONE" indicates that no "--output" value should be '
            'passed to `build_runner`.',
      )
      ..addFlag(_verbose,
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Enables verbose logging.')
      ..addFlag(_requireBuildWebCompilers,
          defaultsTo: true,
          negatable: true,
          help: 'If a dependency on `build_web_compilers` is required to run.');
  }

  List<String> getArgs(PubspecLock pubspecLock) {
    var arguments = <String>[];
    if ((argResults[_release] as bool) ?? releaseDefault) {
      arguments.add('--$_release');
    }

    var output = argResults[_output] as String;
    if (output != null && output != outputNone) {
      arguments.addAll(['--$_output', output]);
    }

    if (argResults[_verbose] as bool) {
      arguments.add('--$_verbose');
    }
    return arguments;
  }

  Future<int> runCore(String command, {List<String> extraArgs}) async {
    var pubspecLock = await PubspecLock.read();
    await checkPubspecLock(pubspecLock,
        requireBuildWebCompilers:
            argResults[_requireBuildWebCompilers] as bool);

    final arguments = [command]
      ..addAll(extraArgs ?? const [])
      ..addAll(getArgs(pubspecLock));

    stdout.write('Creating build script');
    var stopwatch = new Stopwatch()..start();
    var buildRunnerScript = await _buildRunnerScript();
    stdout.writeln(', took ${stopwatch.elapsedMilliseconds}ms');

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
