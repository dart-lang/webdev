// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Wrapper around the incremental frontend server compiler.
abstract class FrontendServerClient {
  /// Compiles the Dart app identified by [entrypoint].
  ///
  /// Most arguments directly mirror the command line arguments for the
  /// frontend_server (see `pkg/frontend_server/lib/frontend_server.dart` in
  /// the sdk). Options are exposed on an as-needed basis.
  ///
  /// The [entrypoint] and [packagesJson] may be a relative path or any uri
  /// supported by the frontend server.
  ///
  /// On successive runs [invalidatedFiles] must be provided, which indicates
  /// the files which have changed. The frontend server _does not_ do any of
  /// its own invalidation.
  ///
  /// The [outputDillPath] determines where the primary output should be, and
  /// some targets may output additional files based on that file name (by
  /// adding file extensions for instance).
  Future<CompileResult> compile(
    String entrypoint,
    String outputDillPath, {
    bool enableHttpUris = false,
    List<String> fileSystemRoots = const [], // For `fileSystemScheme` uris.
    String fileSystemScheme =
        'org-dartlang-root', // Custom scheme for virtual `fileSystemRoots`.
    List<Uri> invalidatedFiles = const [],
    String packagesJson = '.dart_tool/package_config.json',
    String platformKernel, // Defaults to the current SDK platform kernel file.
    String sdkRoot, // Defaults to the current SDK root.
    String target = 'vm', // The kernel target type.
  });

  /// TODO: Document
  Future<CompileResult> compileExpression({
    @required String expression,
    @required List<String> definitions,
    @required bool isStatic,
    @required String klass,
    @required String libraryUri,
    @required List<String> typeDefinitions,
  });

  /// TODO: Document
  Future<CompileResult> compileExpressionToJs({
    @required String expression,
    @required int column,
    @required Map<String, String> jsFrameValues,
    @required Map<String, String> jsModules,
    @required String libraryUri,
    @required int line,
    @required String moduleName,
  });

  /// Should be invoked when results of compilation are accepted by the client.
  ///
  /// Either [accept] or [reject] should be called after every [compile] call.
  void accept();

  /// Should be invoked when results of compilation are rejected by the client.
  ///
  /// Either [accept] or [reject] should be called after every [compile] call.
  Future<CompileResult> reject() => throw UnimplementedError();

  /// Should be invoked when frontend server compiler should forget what was
  /// accepted previously so that next call to [compile] produces complete
  /// kernel file.
  void reset() => throw UnimplementedError();

  /// Stop the service gracefully (using the shutdown command)
  Future<void> shutdown() => throw UnimplementedError();

  /// Kills the service forcefully.
  Future<void> kill() => throw UnimplementedError();
}

/// The result of a compile call.
class CompileResult {
  const CompileResult._(
      {this.dillOutput, this.errors, this.wasIncremental, this.sources});

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

  /// All the transitive sources that are a part of the compiled program.
  final Iterable<Uri> sources;

  /// Whether this was an incremental build.
  final bool wasIncremental;
}
