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

/// Wrapper around the incremental frontend server compiler.
class FrontendServerClient {
  final String _entrypoint;
  final Process _feServer;
  final StreamQueue<String> _feServerStdoutLines;
  var _isCompiling = false;
  var _isFirstCompile = true;

  FrontendServerClient._(
      this._entrypoint, this._feServer, this._feServerStdoutLines) {
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
    bool enableHttpUris = false,
    List<String> fileSystemRoots = const [], // For `fileSystemScheme` uris,
    String fileSystemScheme =
        'org-dartlang-root', // Custom scheme for virtual `fileSystemRoots`.
    String packagesJson = '.dart_tool/package_config.json',
    String sdkRoot, // Defaults to the current SDK root.
    String target = 'vm', // The kernel target type.
  }) async {
    var feServer = await Process.start(_dartBinary, [
      _feServerPath,
      '--sdk-root',
      _sdkDir ?? sdkRoot,
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
      '--no-incremental-serialization',
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
    );
  }

  /// Compiles [_entrypoint], using an incremental recompile if possible.
  ///
  /// [invalidatedUris] must not be empty for all but the very first compile.
  ///
  /// The frontend server _does not_ do any of its own invalidation.
  Future<CompileResult> compile(List<Uri> invalidatedUris) async {
    if (_isCompiling) {
      throw StateError(
          'App is already being compiled, you must wait for that to complete '
          'before asking for another compile.');
    }
    _isCompiling = true;

    try {
      var action = _isFirstCompile ? 'compile' : 'recompile';

      var command = StringBuffer('$action $_entrypoint');
      if (action == 'recompile') {
        assert(invalidatedUris != null && invalidatedUris.isNotEmpty);
        var boundaryKey = Uuid().v4();
        command.writeln(' $boundaryKey');
        assert(invalidatedUris != null);
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
            assert(line == feBoundaryKey);
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

      return CompileResult._(
          dillOutput: null,
          wasIncremental: action == 'recompile',
          newSources: newSources,
          removedSources: removedSources);
    } finally {
      _isCompiling = false;
      _isFirstCompile = false;
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
    _feServer.stdin.writeln('accept');
  }

  /// Should be invoked when results of compilation are rejected by the client.
  ///
  /// Either [accept] or [reject] should be called after every [compile] call.
  void reject() {
    _feServer.stdin.writeln('reject');
  }

  /// Should be invoked when frontend server compiler should forget what was
  /// accepted previously so that next call to [compile] produces complete
  /// kernel file.
  void reset() {
    _feServer.stdin.writeln('reset');
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

  // These only exist if the `target` is `dartdevc`.
  String get jsSourceMapsOutput =>
      dillOutput == null ? null : '$dillOutput.map';
  String get jsSourcesOutput =>
      dillOutput == null ? null : '$dillOutput.sources';
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

enum _FeServerState {
  started,
  waitingForKey,
  gettingSourceDiffs,
  done,
}

final _dartBinary = p.join(_sdkDir, 'bin', 'dart');
final _feServerPath =
    p.join(_sdkDir, 'bin', 'snapshots', 'frontend_server.dart.snapshot');
final _sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
