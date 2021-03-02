// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pedantic/pedantic.dart';
import 'package:usage/uuid/uuid.dart';

import 'utilities.dart';

String get frontendServerExecutable =>
    p.join(dartSdkPath, 'bin', 'snapshots', 'frontend_server.dart.snapshot');

typedef CompilerMessageConsumer = void Function(String message,
    {StackTrace stackTrace});

class CompilerOutput {
  const CompilerOutput(this.outputFilename, this.errorCount, this.sources);

  final String outputFilename;
  final int errorCount;
  final List<Uri> sources;
}

enum StdoutState { collectDiagnostic, collectDependencies }

/// Handles stdin/stdout communication with the frontend server.
class StdoutHandler {
  void _printTrace(String message) {
    Logger.root.info(message);
  }

  StdoutHandler({this.consumer = printError}) {
    reset();
  }

  bool compilerMessageReceived = false;
  final CompilerMessageConsumer consumer;
  String boundaryKey;
  StdoutState state = StdoutState.collectDiagnostic;
  Completer<CompilerOutput> compilerOutput;
  final List<Uri> sources = <Uri>[];

  bool _suppressCompilerMessages;
  bool _expectSources;
  bool _badState = false;

  void handler(String message) {
    if (message.startsWith('Observatory listening')) {
      stderr.writeln(message);
      return;
    }
    if (message.startsWith('Observatory server failed')) {
      throw Exception(message);
    }
    if (_badState) {
      return;
    }
    var kResultPrefix = 'result ';
    if (boundaryKey == null && message.startsWith(kResultPrefix)) {
      boundaryKey = message.substring(kResultPrefix.length);
      return;
    }
    // Invalid state, see commented issue below for more information.
    // NB: both the completeError and _badState flags are required to avoid
    // filling the console with exceptions.
    if (boundaryKey == null) {
      // Throwing a synchronous exception via throwToolExit will fail to cancel
      // the stream. Instead use completeError so that the error is returned
      // from the awaited future that the compiler consumers are expecting.
      compilerOutput.completeError(
          'Frontend server tests encountered an internal problem. '
          'This can be caused by printing to stdout into the stream that is '
          'used for communication between frontend server (in sdk) or '
          'frontend server client (in dwds tests).'
          '\n\n'
          'Additional debugging information:\n'
          '  StdoutState: $state\n'
          '  compilerMessageReceived: $compilerMessageReceived\n'
          '  message: $message\n'
          '  _expectSources: $_expectSources\n'
          '  sources: $sources\n');
      // There are several event turns before the tool actually exits from a
      // tool exception. Normally, the stream should be cancelled to prevent
      // more events from entering the bad state, but because the error
      // is coming from handler itself, there is no clean way to pipe this
      // through. Instead, we set a flag to prevent more messages from
      // registering.
      _badState = true;
      return;
    }
    if (message.startsWith(boundaryKey)) {
      if (_expectSources) {
        if (state == StdoutState.collectDiagnostic) {
          state = StdoutState.collectDependencies;
          return;
        }
      }
      if (message.length <= boundaryKey.length) {
        compilerOutput.complete(null);
        return;
      }
      var spaceDelimiter = message.lastIndexOf(' ');
      compilerOutput.complete(CompilerOutput(
          message.substring(boundaryKey.length + 1, spaceDelimiter),
          int.parse(message.substring(spaceDelimiter + 1).trim()),
          sources));
      return;
    }
    if (state == StdoutState.collectDiagnostic) {
      if (!_suppressCompilerMessages) {
        if (compilerMessageReceived == false) {
          consumer('\nCompiler message:');
          compilerMessageReceived = true;
        }
        consumer(message);
      }
    } else {
      assert(state == StdoutState.collectDependencies);
      switch (message[0]) {
        case '+':
          sources.add(Uri.parse(message.substring(1)));
          break;
        case '-':
          sources.remove(Uri.parse(message.substring(1)));
          break;
        default:
          _printTrace('Unexpected prefix for $message uri - ignoring');
      }
    }
  }

  // This is needed to get ready to process next compilation result output,
  // with its own boundary key and new completer.
  void reset(
      {bool suppressCompilerMessages = false, bool expectSources = true}) {
    boundaryKey = null;
    compilerMessageReceived = false;
    compilerOutput = Completer<CompilerOutput>();
    _suppressCompilerMessages = suppressCompilerMessages;
    _expectSources = expectSources;
    state = StdoutState.collectDiagnostic;
  }
}

/// Converts filesystem paths to package URIs.
class PackageUriMapper {
  PackageUriMapper(String scriptPath, String packagesFilePath,
      String fileSystemScheme, List<String> fileSystemRoots) {
    init(scriptPath, packagesFilePath, fileSystemScheme, fileSystemRoots);
  }

  Future<void> init(String scriptPath, String packagesFilePath,
      String fileSystemScheme, List<String> fileSystemRoots) async {
    var packageConfig = await loadPackageConfig(
        File(fileSystem.path.absolute(packagesFilePath)));
    var isWindowsPath =
        Platform.isWindows && !scriptPath.startsWith('org-dartlang-app');
    var scriptUri = Uri.file(scriptPath, windows: isWindowsPath).toString();
    for (var package in packageConfig.packages) {
      var prefix = package.packageUriRoot.toString();
      // Only perform a multi-root mapping if there are multiple roots.
      if (fileSystemScheme != null &&
          fileSystemRoots != null &&
          fileSystemRoots.length > 1 &&
          prefix.contains(fileSystemScheme)) {
        _packageName = package.name;
        _uriPrefixes = fileSystemRoots
            .map((String name) =>
                Uri.file(name, windows: Platform.isWindows).toString())
            .toList();
        return;
      }
      if (scriptUri.startsWith(prefix)) {
        _packageName = package.name;
        _uriPrefixes = <String>[prefix];
        return;
      }
    }
  }

  String _packageName;
  List<String> _uriPrefixes;

  Uri map(String scriptPath) {
    if (_packageName == null) {
      return null;
    }
    var scriptUri =
        Uri.file(scriptPath, windows: Platform.isWindows).toString();
    for (var uriPrefix in _uriPrefixes) {
      if (scriptUri.startsWith(uriPrefix)) {
        return Uri.parse(
            'package:$_packageName/${scriptUri.substring(uriPrefix.length)}');
      }
    }
    return null;
  }

  static Uri findUri(String scriptPath, String packagesFilePath,
      String fileSystemScheme, List<String> fileSystemRoots) {
    return PackageUriMapper(
            scriptPath, packagesFilePath, fileSystemScheme, fileSystemRoots)
        .map(scriptPath);
  }
}

/// Class that allows to serialize compilation requests to the compiler.
abstract class _CompilationRequest {
  _CompilationRequest(this.completer);

  Completer<CompilerOutput> completer;

  Future<CompilerOutput> _run(DefaultResidentCompiler compiler);

  Future<void> run(DefaultResidentCompiler compiler) async {
    completer.complete(await _run(compiler));
  }
}

class _RecompileRequest extends _CompilationRequest {
  _RecompileRequest(
    Completer<CompilerOutput> completer,
    this.mainPath,
    this.invalidatedFiles,
    this.outputPath,
    this.packagesFilePath,
  ) : super(completer);

  String mainPath;
  List<Uri> invalidatedFiles;
  String outputPath;
  String packagesFilePath;

  @override
  Future<CompilerOutput> _run(DefaultResidentCompiler compiler) async =>
      compiler._recompile(this);
}

class _CompileExpressionToJsRequest extends _CompilationRequest {
  _CompileExpressionToJsRequest(
      Completer<CompilerOutput> completer,
      this.libraryUri,
      this.line,
      this.column,
      this.jsModules,
      this.jsFrameValues,
      this.moduleName,
      this.expression)
      : super(completer);

  String libraryUri;
  int line;
  int column;
  Map<String, String> jsModules;
  Map<String, String> jsFrameValues;
  String moduleName;
  String expression;

  @override
  Future<CompilerOutput> _run(DefaultResidentCompiler compiler) async =>
      compiler._compileExpressionToJs(this);
}

class _RejectRequest extends _CompilationRequest {
  _RejectRequest(Completer<CompilerOutput> completer) : super(completer);

  @override
  Future<CompilerOutput> _run(DefaultResidentCompiler compiler) async =>
      compiler._reject();
}

/// Wrapper around incremental frontend server compiler, that communicates with
/// server via stdin/stdout.
///
/// The wrapper is intended to stay resident in memory as user changes, reloads,
/// restarts the Flutter app.
abstract class ResidentCompiler {
  factory ResidentCompiler(
    String sdkRoot, {
    String packagesPath,
    List<String> fileSystemRoots,
    String fileSystemScheme,
    String platformDill,
    bool soundNullSafety,
    bool verbose,
    CompilerMessageConsumer compilerMessageConsumer,
  }) = DefaultResidentCompiler;

  // TODO(jonahwilliams): find a better way to configure additional file system
  // roots from the runner.
  // See: https://github.com/flutter/flutter/issues/50494
  void addFileSystemRoot(String root);

  /// If invoked for the first time, it compiles Dart script identified by
  /// [mainPath], [invalidatedFiles] list is ignored.
  /// On successive runs [invalidatedFiles] indicates which files need to be
  /// recompiled. If [mainPath] is null, previously used [mainPath] entry
  /// point that is used for recompilation.
  /// Binary file name is returned if compilation was successful, otherwise
  /// null is returned.
  Future<CompilerOutput> recompile(
    String mainPath,
    List<Uri> invalidatedFiles, {
    @required String outputPath,
    String packagesFilePath,
  });

  /// Compiles [expression] in [libraryUri] at[line]:[column] to JavaScript
  /// in [moduleName].
  ///
  /// Values listed in [jsFrameValues] are substituted for their names in the
  /// [expression].
  ///
  /// Ensures that all [jsModules] are loaded and accessible inside the
  /// expression.
  ///
  /// Returns [ExpressionCompilationResult]
  /// Errors are reported using onDiagnostic function
  /// [moduleName] is of the form '/packages/hello_world_main.dart'
  /// [jsFrameValues] is a map from js variable name to its primitive value
  /// or another variable name, for example
  /// { 'x': '1', 'y': 'y', 'o': 'null' }
  /// [jsModules] is a map from variable name to the module name, where
  /// variable name is the name originally used in JavaScript to contain the
  /// module object, for example:
  /// { 'dart':'dart_sdk', 'main': '/packages/hello_world_main.dart' }
  Future<CompilerOutput> compileExpressionToJs(
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression);

  /// Should be invoked when results of compilation are accepted by the client.
  ///
  /// Either [accept] or [reject] should be called after every [recompile] call.
  void accept();

  /// Should be invoked when results of compilation are rejected by the client.
  ///
  /// Either [accept] or [reject] should be called after every [recompile] call.
  Future<CompilerOutput> reject();

  /// Should be invoked when frontend server compiler should forget what was
  /// accepted previously so that next call to [recompile] produces complete
  /// kernel file.
  void reset();

  /// stop the service normally
  Future<dynamic> shutdown();

  /// kill the service
  Future<dynamic> kill();
}

@visibleForTesting
class DefaultResidentCompiler implements ResidentCompiler {
  DefaultResidentCompiler(
    String sdkRoot, {
    this.packagesPath,
    this.fileSystemRoots,
    this.fileSystemScheme,
    this.platformDill,
    this.soundNullSafety,
    this.verbose,
    CompilerMessageConsumer compilerMessageConsumer = printError,
  })  : assert(sdkRoot != null),
        _stdoutHandler = StdoutHandler(consumer: compilerMessageConsumer),
        // This is a URI, not a file path, so the forward slash is correct even on Windows.
        sdkRoot = sdkRoot.endsWith('/') ? sdkRoot : '$sdkRoot/';

  final String packagesPath;
  final List<String> fileSystemRoots;
  final String fileSystemScheme;
  final String platformDill;
  final bool soundNullSafety;
  final bool verbose;

  void _printTrace(String message) {
    Logger.root.info(message);
  }

  @override
  void addFileSystemRoot(String root) {
    fileSystemRoots.add(root);
  }

  /// The path to the root of the Dart SDK used to compile.
  final String sdkRoot;

  Process _server;
  final StdoutHandler _stdoutHandler;
  bool _compileRequestNeedsConfirmation = false;

  final StreamController<_CompilationRequest> _controller =
      StreamController<_CompilationRequest>();

  @override
  Future<CompilerOutput> recompile(String mainPath, List<Uri> invalidatedFiles,
      {@required String outputPath, String packagesFilePath}) async {
    assert(outputPath != null);
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    var completer = Completer<CompilerOutput>();
    _controller.add(_RecompileRequest(
        completer, mainPath, invalidatedFiles, outputPath, packagesFilePath));
    return completer.future;
  }

  Future<CompilerOutput> _recompile(_RecompileRequest request) async {
    _stdoutHandler.reset();

    // First time recompile is called we actually have to compile the app from
    // scratch ignoring list of invalidated files.
    PackageUriMapper packageUriMapper;
    if (request.packagesFilePath != null) {
      packageUriMapper = PackageUriMapper(
        request.mainPath,
        request.packagesFilePath,
        fileSystemScheme,
        fileSystemRoots,
      );
    }

    _compileRequestNeedsConfirmation = true;

    if (_server == null) {
      return _compile(_mapFilename(request.mainPath, packageUriMapper),
          request.outputPath, request.packagesFilePath);
    }

    var inputKey = Uuid().generateV4();
    var mainUri = request.mainPath != null
        ? '${_mapFilename(request.mainPath, packageUriMapper)} '
        : '';
    _server.stdin.writeln('recompile $mainUri$inputKey');
    _printTrace('<- recompile $mainUri$inputKey');
    for (var fileUri in request.invalidatedFiles) {
      var message = _mapFileUri(fileUri.toString(), packageUriMapper);
      _server.stdin.writeln(message);
      _printTrace(message);
    }
    _server.stdin.writeln(inputKey);
    _printTrace('<- $inputKey');

    return _stdoutHandler.compilerOutput.future;
  }

  final List<_CompilationRequest> _compilationQueue = <_CompilationRequest>[];

  Future<void> _handleCompilationRequest(_CompilationRequest request) async {
    var isEmpty = _compilationQueue.isEmpty;
    _compilationQueue.add(request);
    // Only trigger processing if queue was empty - i.e. no other requests
    // are currently being processed. This effectively enforces "one
    // compilation request at a time".
    if (isEmpty) {
      while (_compilationQueue.isNotEmpty) {
        var request = _compilationQueue.first;
        await request.run(this);
        _compilationQueue.removeAt(0);
      }
    }
  }

  Future<CompilerOutput> _compile(
      String scriptUri, String outputFilePath, String packagesFilePath) async {
    var frontendServer = frontendServerExecutable;
    var args = <String>[
      frontendServer,
      '--sdk-root',
      sdkRoot,
      '--incremental',
      '--target=dartdevc',
      '-Ddart.developer.causal_async_stacks=true',
      '--output-dill',
      outputFilePath,
      if (packagesFilePath != null) ...<String>[
        '--packages',
        packagesFilePath,
      ] else if (packagesPath != null) ...<String>[
        '--packages',
        packagesPath,
      ],
      if (fileSystemRoots != null)
        for (final String root in fileSystemRoots) ...<String>[
          '--filesystem-root',
          root,
        ],
      if (fileSystemScheme != null) ...<String>[
        '--filesystem-scheme',
        fileSystemScheme,
      ],
      if (platformDill != null) ...<String>[
        '--platform',
        platformDill,
      ],
      '--debugger-module-names',
      '--experimental-emit-debug-metadata',
      soundNullSafety ? '--sound-null-safety' : '--no-sound-null-safety',
      if (verbose) '--verbose'
    ];

    _printTrace(args.join(' '));
    _server = await Process.start(Platform.resolvedExecutable, args,
        workingDirectory: packagesPath);
    _server.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_stdoutHandler.handler, onDone: () {
      // when outputFilename future is not completed, but stdout is closed
      // process has died unexpectedly.
      if (!_stdoutHandler.compilerOutput.isCompleted) {
        _stdoutHandler.compilerOutput.complete(null);
        throw Exception('the Dart compiler exited unexpectedly.');
      }
    });

    _server.stderr
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(printError);

    unawaited(_server.exitCode.then((int code) {
      if (code != 0) {
        throw Exception('the Dart compiler exited unexpectedly.');
      }
    }));

    _server.stdin.writeln('compile $scriptUri');
    _printTrace('<- compile $scriptUri');

    return _stdoutHandler.compilerOutput.future;
  }

  @override
  Future<CompilerOutput> compileExpressionToJs(
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression) {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    var completer = Completer<CompilerOutput>();
    _controller.add(_CompileExpressionToJsRequest(completer, libraryUri, line,
        column, jsModules, jsFrameValues, moduleName, expression));
    return completer.future;
  }

  Future<CompilerOutput> _compileExpressionToJs(
      _CompileExpressionToJsRequest request) async {
    _stdoutHandler.reset(
        suppressCompilerMessages: !verbose, expectSources: false);

    // 'compile-expression-to-js' should be invoked after compiler has been started,
    // program was compiled.
    if (_server == null) {
      return null;
    }

    var inputKey = Uuid().generateV4();
    _server.stdin.writeln('compile-expression-to-js $inputKey');
    _server.stdin.writeln(request.libraryUri ?? '');
    _server.stdin.writeln(request.line);
    _server.stdin.writeln(request.column);
    request.jsModules?.forEach((k, v) {
      _server.stdin.writeln('$k:$v');
    });
    _server.stdin.writeln(inputKey);
    request.jsFrameValues?.forEach((k, v) {
      _server.stdin.writeln('$k:$v');
    });
    _server.stdin.writeln(inputKey);
    _server.stdin.writeln(request.moduleName ?? '');
    _server.stdin.writeln(request.expression ?? '');

    return _stdoutHandler.compilerOutput.future;
  }

  @override
  void accept() {
    if (_compileRequestNeedsConfirmation) {
      _server.stdin.writeln('accept');
      _printTrace('<- accept');
    }
    _compileRequestNeedsConfirmation = false;
  }

  @override
  Future<CompilerOutput> reject() {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    var completer = Completer<CompilerOutput>();
    _controller.add(_RejectRequest(completer));
    return completer.future;
  }

  Future<CompilerOutput> _reject() {
    if (!_compileRequestNeedsConfirmation) {
      return Future<CompilerOutput>.value(null);
    }
    _stdoutHandler.reset(expectSources: false);
    _server.stdin.writeln('reject');
    _printTrace('<- reject');
    _compileRequestNeedsConfirmation = false;
    return _stdoutHandler.compilerOutput.future;
  }

  @override
  void reset() {
    _server?.stdin?.writeln('reset');
    _printTrace('<- reset');
  }

  Future<int> quit() async {
    _server.stdin.writeln('quit');
    _printTrace('<- quit');
    return _server.exitCode;
  }

  String _mapFilename(String filename, PackageUriMapper packageUriMapper) {
    return _doMapFilename(filename, packageUriMapper) ?? filename;
  }

  String _mapFileUri(String fileUri, PackageUriMapper packageUriMapper) {
    String filename;
    try {
      filename = Uri.parse(fileUri).toFilePath();
    } on UnsupportedError catch (_) {
      return fileUri;
    }
    return _doMapFilename(filename, packageUriMapper) ?? fileUri;
  }

  String _doMapFilename(String filename, PackageUriMapper packageUriMapper) {
    if (packageUriMapper != null) {
      var packageUri = packageUriMapper.map(filename);
      if (packageUri != null) {
        return packageUri.toString();
      }
    }

    if (fileSystemRoots != null) {
      for (var root in fileSystemRoots) {
        if (filename.startsWith(root)) {
          return Uri(
                  scheme: fileSystemScheme,
                  path: filename.substring(root.length))
              .toString();
        }
      }
    }
    if (Platform.isWindows &&
        fileSystemRoots != null &&
        fileSystemRoots.length > 1) {
      return Uri.file(filename, windows: Platform.isWindows).toString();
    }
    return null;
  }

  @override
  Future<dynamic> shutdown() async {
    // Server was never successfully created.
    if (_server == null) {
      return 0;
    }
    return quit();
  }

  @override
  Future<dynamic> kill() async {
    if (_server == null) {
      return 0;
    }

    _printTrace('killing pid ${_server.pid}');
    _server.kill();
    return _server.exitCode;
  }
}

class TestExpressionCompiler implements ExpressionCompiler {
  final ResidentCompiler _generator;
  TestExpressionCompiler(this._generator);

  @override
  Future<ExpressionCompilationResult> compileExpressionToJs(
      String isolateId,
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression) async {
    var compilerOutput = await _generator.compileExpressionToJs(libraryUri,
        line, column, jsModules, jsFrameValues, moduleName, expression);

    if (compilerOutput != null && compilerOutput.outputFilename != null) {
      var content = utf8.decode(
          fileSystem.file(compilerOutput.outputFilename).readAsBytesSync());
      return ExpressionCompilationResult(
          content, compilerOutput.errorCount > 0);
    }

    throw Exception('Failed to compile $expression');
  }

  @override
  Future<bool> updateDependencies(Map<String, ModuleInfo> modules) async =>
      true;

  @override
  Future<void> initialize({String moduleFormat, bool soundNullSafety}) async {}
}
