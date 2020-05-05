// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'shared.dart';

/// Wrapper around the incremental frontend server compiler.
class FrontendServerClient {
  final String _entrypoint;
  final Process _feServer;
  final StreamQueue<String> _feServerStdoutLines;
  final String _outputDillPath;

  _ClientState _state;

  FrontendServerClient._(this._entrypoint, this._feServer,
      this._feServerStdoutLines, this._outputDillPath)
      : _state = _ClientState.waitingForFirstCompile {
    _feServer.stderr.transform(utf8.decoder).listen(stderr.write);
  }

  /// Starts the frontend server.
  ///
  /// Most arguments directly mirror the command line arguments for the
  /// frontend_server (see `pkg/frontend_server/lib/frontend_server.dart` in
  /// the sdk). Options are exposed on an as-needed basis.
  ///
  /// The [entrypoint] and [packagesJson] may be a relative path or any uri
  /// supported by the frontend server.
  ///
  /// The [outputDillPath] determines where the primary output should be, and
  /// some targets may output additional files based on that file name (by
  /// adding file extensions for instance).
  static Future<FrontendServerClient> start(
    String entrypoint,
    String outputDillPath,
    String platformKernel, {
    bool debug = false,
    bool enableHttpUris = false,
    List<String> fileSystemRoots = const [], // For `fileSystemScheme` uris,
    String fileSystemScheme =
        'org-dartlang-root', // Custom scheme for virtual `fileSystemRoots`.
    String packagesJson = '.dart_tool/package_config.json',
    String sdkRoot, // Defaults to the current SDK root.
    String target = 'vm', // The kernel target type.
  }) async {
    var feServer = await Process.start(Platform.resolvedExecutable, [
      if (debug) '--observe',
      _feServerPath,
      '--sdk-root',
      sdkDir ?? sdkRoot,
      '--platform=$platformKernel',
      '--target=$target',
      for (var root in fileSystemRoots) '--filesystem-root=$root',
      '--filesystem-scheme',
      fileSystemScheme,
      '--output-dill',
      outputDillPath,
      '--packages=$packagesJson',
      if (enableHttpUris) '--enable-http-uris',
      '--incremental',
    ]);
    var feServerStdoutLines = StreamQueue(feServer.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter()));

    // The frontend_server doesn't appear to recursively create files, so we
    //  need to make sure the output dir already exists.
    var outputDir = Directory(p.dirname(outputDillPath));
    if (!await outputDir.exists()) await outputDir.create();

    return FrontendServerClient._(
      entrypoint,
      feServer,
      feServerStdoutLines,
      outputDillPath,
    );
  }

  /// Compiles [_entrypoint], using an incremental recompile if possible.
  ///
  /// [invalidatedUris] must not be null for all but the very first compile.
  ///
  /// The frontend server _does not_ do any of its own invalidation.
  Future<CompileResult> compile([List<Uri> invalidatedUris]) async {
    String action;
    switch (_state) {
      case _ClientState.waitingForFirstCompile:
        action = 'compile';
        break;
      case _ClientState.waitingForRecompile:
        action = 'recompile';
        break;
      case _ClientState.waitingForAcceptOrReject:
        throw StateError(
            'Previous `CompileResult` must be accepted or rejected by '
            'calling `accept` or `reject`.');
      case _ClientState.compiling:
        throw StateError(
            'App is already being compiled, you must wait for that to '
            'complete and `accept` or `reject` the result before compiling '
            'again.');
    }
    _state = _ClientState.compiling;

    try {
      var command = StringBuffer('$action $_entrypoint');
      if (action == 'recompile') {
        if (invalidatedUris == null || invalidatedUris.isEmpty) {
          throw StateError(
              'Subsequent compile invocations must provide a non-empty list '
              'of invalidated uris.');
        }
        var boundaryKey = Uuid().v4();
        command.writeln(' $boundaryKey');
        for (var uri in invalidatedUris) {
          command.writeln('$uri');
        }
        command.write(boundaryKey);
      }

      _feServer.stdin.writeln(command);
      var state = _FeServerState.started;
      String feBoundaryKey;
      var newSources = <Uri>{};
      var removedSources = <Uri>{};
      while (
          state != _FeServerState.done && await _feServerStdoutLines.hasNext) {
        var line = await _feServerStdoutLines.next;
        switch (state) {
          case _FeServerState.started:
            assert(line.startsWith('result'));
            feBoundaryKey = line.substring(line.indexOf(' ') + 1);
            state = _FeServerState.waitingForKey;
            continue;
          case _FeServerState.waitingForKey:
            assert(line == feBoundaryKey, line);
            state = _FeServerState.gettingSourceDiffs;
            continue;
          case _FeServerState.gettingSourceDiffs:
            if (line.startsWith(feBoundaryKey)) {
              state = _FeServerState.done;
              continue;
            }
            var diffUri = Uri.parse(line.substring(1));
            if (line.startsWith('+')) {
              newSources.add(diffUri);
            } else if (line.startsWith('-')) {
              removedSources.add(diffUri);
            } else {
              throw StateError(
                  'unrecognized diff line, should start with a + or - but got: $line');
            }
            continue;
          case _FeServerState.done:
            throw StateError('Unreachable');
        }
      }

      var wasIncremental = action == 'recompile';
      return CompileResult._(
          dillOutput: wasIncremental
              ? '$_outputDillPath.incremental.dill'
              : _outputDillPath,
          wasIncremental: wasIncremental,
          newSources: newSources,
          removedSources: removedSources);
    } finally {
      _state = _ClientState.waitingForAcceptOrReject;
    }
  }

  /// TODO: Document
  Future<CompileResult> compileExpression({
    @required String expression,
    @required List<String> definitions,
    @required bool isStatic,
    @required String klass,
    @required String libraryUri,
    @required List<String> typeDefinitions,
  }) =>
      throw UnimplementedError();

  /// TODO: Document
  Future<CompileResult> compileExpressionToJs({
    @required String expression,
    @required int column,
    @required Map<String, String> jsFrameValues,
    @required Map<String, String> jsModules,
    @required String libraryUri,
    @required int line,
    @required String moduleName,
  }) =>
      throw UnimplementedError();

  /// Should be invoked when results of compilation are accepted by the client.
  ///
  /// Either [accept] or [reject] should be called after every [compile] call.
  void accept() {
    if (_state != _ClientState.waitingForAcceptOrReject) {
      throw StateError(
          'Called `accept` but there was no previous compile to accept.');
    }
    _feServer.stdin.writeln('accept');
    _state = _ClientState.waitingForRecompile;
  }

  /// Should be invoked when results of compilation are rejected by the client.
  ///
  /// Either [accept] or [reject] should be called after every [compile] call.
  void reject() {
    if (_state != _ClientState.waitingForAcceptOrReject) {
      throw StateError(
          'Called `reject` but there was no previous compile to reject.');
    }
    _feServer.stdin.writeln('reject');
    _state = _ClientState.waitingForFirstCompile;
  }

  /// Should be invoked when frontend server compiler should forget what was
  /// accepted previously so that next call to [compile] produces complete
  /// kernel file.
  void reset() {
    if (_state == _ClientState.compiling) {
      throw StateError(
          'Called `reset` during an active compile, you must wait for that to '
          'complete first.');
    }
    _feServer.stdin.writeln('reset');
    _state = _ClientState.waitingForFirstCompile;
  }

  /// Stop the service gracefully (using the shutdown command)
  Future<int> shutdown() {
    _feServerStdoutLines.cancel();
    _feServer.stdin.writeln('quit');
    return _feServer.exitCode;
  }

  /// Kills the server forcefully by calling `kill` on the process, and
  /// returns the result.
  bool kill({ProcessSignal processSignal = ProcessSignal.sigterm}) {
    _feServerStdoutLines.cancel();
    return _feServer.kill(processSignal);
  }
}

/// The result of a compile call.
class CompileResult {
  const CompileResult._(
      {this.dillOutput,
      this.errors,
      this.wasIncremental,
      this.newSources,
      this.removedSources});

  /// The produced dill output file, this will either be a full dill file or an
  /// incremental dill file depending on [wasIncremental].
  ///
  /// May be `null` if [errors] is not empty.
  final String dillOutput;

  /// Any errors encountered during compilation.
  final Iterable<String> errors;

  /// A single file containing all source maps for all JS outputs.
  ///
  /// Read [jsManifestOutput] for file offsets for each sourcemap.
  ///
  /// Will be `null` if [dillOutput] is `null`.
  String get jsSourceMapsOutput =>
      dillOutput == null ? null : '$dillOutput.map';

  /// A single file containing all JS outputs.
  ///
  /// Read [jsManifestOutput] for file offsets for each source.
  ///
  /// Will be `null` if [dillOutput] is `null`.
  String get jsSourcesOutput =>
      dillOutput == null ? null : '$dillOutput.sources';

  /// A JSON manifest containing offsets for the sources and source maps in
  /// the [jsSourcesOutput] and [jsSourceMapsOutput] files.
  ///
  /// Will be `null` if [dillOutput] is `null`.
  String get jsManifestOutput => dillOutput == null ? null : '$dillOutput.json';

  /// All the transitive source dependencies that were added as a part of this
  /// compile.
  final Iterable<Uri> newSources;

  /// All the transitive source dependencies that were removed as a part of
  /// this compile.
  final Iterable<Uri> removedSources;

  /// Whether this was an incremental build.
  final bool wasIncremental;
}

/// Internal states for the client.
enum _ClientState {
  compiling,
  waitingForAcceptOrReject,
  waitingForFirstCompile,
  waitingForRecompile,
}

/// States for our interaction with the compiler itself.
enum _FeServerState {
  started,
  waitingForKey,
  gettingSourceDiffs,
  done,
}

final _feServerPath =
    p.join(sdkDir, 'bin', 'snapshots', 'frontend_server.dart.snapshot');
