// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:usage/uuid/uuid.dart';

import 'utilities.dart';

Logger _logger = Logger('FrontendServerClient');
Logger _serverLogger = Logger('FrontendServer');

void defaultConsumer(String message, {StackTrace? stackTrace}) =>
    stackTrace == null
        ? _serverLogger.info(message)
        : _serverLogger.severe(message, null, stackTrace);

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
  StdoutHandler({required this.consumer}) {
    reset();
  }

  bool compilerMessageReceived = false;
  final CompilerMessageConsumer consumer;
  String? boundaryKey;
  StdoutState state = StdoutState.collectDiagnostic;
  late Completer<CompilerOutput?> compilerOutput;
  final List<Uri> sources = <Uri>[];

  late bool _suppressCompilerMessages;
  late bool _expectSources;
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
    if (message.startsWith(boundaryKey!)) {
      if (_expectSources) {
        if (state == StdoutState.collectDiagnostic) {
          state = StdoutState.collectDependencies;
          return;
        }
      }
      if (message.length <= boundaryKey!.length) {
        compilerOutput.complete(null);
        return;
      }
      var spaceDelimiter = message.lastIndexOf(' ');
      compilerOutput.complete(CompilerOutput(
          message.substring(boundaryKey!.length + 1, spaceDelimiter),
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
          _logger.warning('Unexpected prefix for $message uri - ignoring');
      }
    }
  }

  // This is needed to get ready to process next compilation result output,
  // with its own boundary key and new completer.
  void reset(
      {bool suppressCompilerMessages = false, bool expectSources = true}) {
    boundaryKey = null;
    compilerMessageReceived = false;
    compilerOutput = Completer<CompilerOutput?>();
    _suppressCompilerMessages = suppressCompilerMessages;
    _expectSources = expectSources;
    state = StdoutState.collectDiagnostic;
  }
}

/// Class that allows to serialize compilation requests to the compiler.
abstract class _CompilationRequest {
  _CompilationRequest(this.completer);

  Completer<CompilerOutput?> completer;

  Future<CompilerOutput?> _run(ResidentCompiler compiler);

  Future<void> run(ResidentCompiler compiler) async {
    completer.complete(await _run(compiler));
  }
}

class _RecompileRequest extends _CompilationRequest {
  _RecompileRequest(
    Completer<CompilerOutput?> completer,
    this.mainUri,
    this.invalidatedFiles,
    this.outputPath,
    this.packageConfig,
  ) : super(completer);

  Uri mainUri;
  List<Uri> invalidatedFiles;
  String outputPath;
  PackageConfig packageConfig;

  @override
  Future<CompilerOutput?> _run(ResidentCompiler compiler) async =>
      compiler._recompile(this);
}

class _CompileExpressionRequest extends _CompilationRequest {
  _CompileExpressionRequest(
    Completer<CompilerOutput?> completer,
    this.expression,
    this.definitions,
    this.typeDefinitions,
    this.libraryUri,
    this.klass,
    this.isStatic,
  ) : super(completer);

  String expression;
  List<String> definitions;
  List<String> typeDefinitions;
  String? libraryUri;
  String? klass;
  bool? isStatic;

  @override
  Future<CompilerOutput?> _run(ResidentCompiler compiler) async =>
      compiler._compileExpression(this);
}

class _CompileExpressionToJsRequest extends _CompilationRequest {
  _CompileExpressionToJsRequest(
      Completer<CompilerOutput?> completer,
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
  Future<CompilerOutput?> _run(ResidentCompiler compiler) async =>
      compiler._compileExpressionToJs(this);
}

class _RejectRequest extends _CompilationRequest {
  _RejectRequest(Completer<CompilerOutput?> completer) : super(completer);

  @override
  Future<CompilerOutput?> _run(ResidentCompiler compiler) async =>
      compiler._reject();
}

/// Wrapper around incremental frontend server compiler, that communicates with
/// server via stdin/stdout.
///
/// The wrapper is intended to stay resident in memory as user changes, reloads,
/// restarts the Flutter app.
class ResidentCompiler {
  ResidentCompiler(
    this.sdkRoot, {
    required this.projectDirectory,
    required this.packageConfigFile,
    required this.fileSystemRoots,
    required this.fileSystemScheme,
    required this.platformDill,
    this.verbose = false,
    CompilerMessageConsumer compilerMessageConsumer = defaultConsumer,
  }) : _stdoutHandler = StdoutHandler(consumer: compilerMessageConsumer);

  final Uri projectDirectory;
  final Uri packageConfigFile;
  final List<Uri> fileSystemRoots;
  final String fileSystemScheme;
  final String platformDill;
  final bool verbose;

  /// The path to the root of the Dart SDK used to compile.
  final String sdkRoot;

  Process? _server;
  final StdoutHandler _stdoutHandler;
  bool _compileRequestNeedsConfirmation = false;

  final StreamController<_CompilationRequest> _controller =
      StreamController<_CompilationRequest>();

  /// If invoked for the first time, it compiles Dart script identified by
  /// [mainUri], [invalidatedFiles] list is ignored.
  /// On successive runs [invalidatedFiles] indicates which files need to be
  /// recompiled. If [mainUri] is null, previously used [mainUri] entry
  /// point that is used for recompilation.
  /// Binary file name is returned if compilation was successful, otherwise
  /// null is returned.
  Future<CompilerOutput?> recompile(
    Uri mainUri,
    List<Uri> invalidatedFiles, {
    required String outputPath,
    required PackageConfig packageConfig,
  }) async {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    var completer = Completer<CompilerOutput?>();
    _controller.add(_RecompileRequest(
        completer, mainUri, invalidatedFiles, outputPath, packageConfig));
    return completer.future;
  }

  Future<CompilerOutput?> _recompile(_RecompileRequest request) async {
    _stdoutHandler.reset();

    final mainUri = request.packageConfig
            .toPackageUri(request.mainUri)
            ?.toString() ??
        _toMultiRootPath(request.mainUri, fileSystemScheme, fileSystemRoots);

    _compileRequestNeedsConfirmation = true;

    if (_server == null) {
      return _compile(mainUri, request.outputPath);
    }
    var server = _server!;

    var inputKey = Uuid().generateV4();
    server.stdin.writeln('recompile $mainUri$inputKey');
    _logger.info('<- recompile $mainUri$inputKey');
    for (var fileUri in request.invalidatedFiles) {
      String message;
      if (fileUri.scheme == 'package') {
        message = fileUri.toString();
      } else {
        message = request.packageConfig.toPackageUri(fileUri)?.toString() ??
            _toMultiRootPath(fileUri, fileSystemScheme, fileSystemRoots);
      }
      server.stdin.writeln(message);
      _logger.info(message);
    }
    server.stdin.writeln(inputKey);
    _logger.info('<- $inputKey');

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

  Future<CompilerOutput?> _compile(
      String scriptUri, String outputFilePath) async {
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
      ...<String>[
        '--packages',
        '$packageConfigFile',
      ],
      for (final root in fileSystemRoots) ...<String>[
        '--filesystem-root',
        '$root',
      ],
      ...<String>[
        '--filesystem-scheme',
        fileSystemScheme,
      ],
      ...<String>[
        '--platform',
        platformDill,
      ],
      '--debugger-module-names',
      '--experimental-emit-debug-metadata',
      if (verbose) '--verbose'
    ];

    _logger.info(args.join(' '));
    final workingDirectory = projectDirectory.toFilePath();
    _server = await Process.start(Platform.resolvedExecutable, args,
        workingDirectory: workingDirectory);

    var server = _server!;
    server.stdout
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

    server.stderr
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_logger.info);

    unawaited(server.exitCode.then((int code) {
      if (code != 0) {
        throw Exception('the Dart compiler exited unexpectedly.');
      }
    }));

    server.stdin.writeln('compile $scriptUri');
    _logger.info('<- compile $scriptUri');

    return _stdoutHandler.compilerOutput.future;
  }

  /// Compile dart expression to kernel.
  Future<CompilerOutput?> compileExpression(
    String expression,
    List<String> definitions,
    List<String> typeDefinitions,
    String libraryUri,
    String klass,
    bool isStatic,
  ) {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    var completer = Completer<CompilerOutput?>();
    _controller.add(_CompileExpressionRequest(completer, expression,
        definitions, typeDefinitions, libraryUri, klass, isStatic));
    return completer.future;
  }

  Future<CompilerOutput?> _compileExpression(
      _CompileExpressionRequest request) async {
    _stdoutHandler.reset(suppressCompilerMessages: true, expectSources: false);

    // 'compile-expression' should be invoked after compiler has been started,
    // program was compiled.
    if (_server == null) {
      return null;
    }
    var server = _server!;

    var inputKey = Uuid().generateV4();
    server.stdin.writeln('compile-expression $inputKey');
    server.stdin.writeln(request.expression);
    request.definitions.forEach(server.stdin.writeln);
    server.stdin.writeln(inputKey);
    request.typeDefinitions.forEach(server.stdin.writeln);
    server.stdin.writeln(inputKey);
    server.stdin.writeln(request.libraryUri ?? '');
    server.stdin.writeln(request.klass ?? '');
    server.stdin.writeln(request.isStatic ?? false);

    return _stdoutHandler.compilerOutput.future;
  }

  /// Compiles dart expression to JavaScript.
  Future<CompilerOutput?> compileExpressionToJs(
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

    var completer = Completer<CompilerOutput?>();
    _controller.add(_CompileExpressionToJsRequest(completer, libraryUri, line,
        column, jsModules, jsFrameValues, moduleName, expression));
    return completer.future;
  }

  Future<CompilerOutput?> _compileExpressionToJs(
      _CompileExpressionToJsRequest request) async {
    _stdoutHandler.reset(
        suppressCompilerMessages: !verbose, expectSources: false);

    // 'compile-expression-to-js' should be invoked after compiler has been started,
    // program was compiled.
    if (_server == null) {
      return null;
    }
    var server = _server!;

    var inputKey = Uuid().generateV4();
    server.stdin.writeln('compile-expression-to-js $inputKey');
    server.stdin.writeln(request.libraryUri);
    server.stdin.writeln(request.line);
    server.stdin.writeln(request.column);
    request.jsModules.forEach((k, v) {
      server.stdin.writeln('$k:$v');
    });
    server.stdin.writeln(inputKey);
    request.jsFrameValues.forEach((k, v) {
      server.stdin.writeln('$k:$v');
    });
    server.stdin.writeln(inputKey);
    server.stdin.writeln(request.moduleName);
    server.stdin.writeln(request.expression);

    return _stdoutHandler.compilerOutput.future;
  }

  /// Should be invoked when results of compilation are accepted by the client.
  ///
  /// Either [accept] or [reject] should be called after every [recompile] call.
  void accept() {
    if (_compileRequestNeedsConfirmation) {
      _server!.stdin.writeln('accept');
      _logger.info('<- accept');
    }
    _compileRequestNeedsConfirmation = false;
  }

  /// Should be invoked when results of compilation are rejected by the client.
  ///
  /// Either [accept] or [reject] should be called after every [recompile] call.
  Future<CompilerOutput?> reject() {
    if (!_controller.hasListener) {
      _controller.stream.listen(_handleCompilationRequest);
    }

    var completer = Completer<CompilerOutput?>();
    _controller.add(_RejectRequest(completer));
    return completer.future;
  }

  Future<CompilerOutput?> _reject() {
    if (!_compileRequestNeedsConfirmation) {
      return Future<CompilerOutput?>.value(null);
    }
    _stdoutHandler.reset(expectSources: false);
    _server!.stdin.writeln('reject');
    _logger.info('<- reject');
    _compileRequestNeedsConfirmation = false;
    return _stdoutHandler.compilerOutput.future;
  }

  /// Should be invoked when frontend server compiler should forget what was
  /// accepted previously so that next call to [recompile] produces complete
  /// kernel file.
  void reset() {
    _server?.stdin.writeln('reset');
    _logger.info('<- reset');
  }

  Future<int> quit() async {
    _server?.stdin.writeln('quit');
    _logger.info('<- quit');

    if (_server == null) {
      return 0;
    }
    return _server!.exitCode;
  }

  /// stop the service normally
  Future<dynamic> shutdown() async {
    // Server was never successfully created.
    if (_server == null) {
      return 0;
    }
    return quit();
  }

  /// kill the service
  Future<dynamic> kill() async {
    if (_server == null) {
      return 0;
    }

    var server = _server!;
    _logger.info('killing pid ${server.pid}');
    server.kill();
    return server.exitCode;
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

    if (compilerOutput != null) {
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
  Future<void> initialize(
      {required String moduleFormat, bool soundNullSafety = false}) async {}
}

/// Convert a file URI into a multi-root scheme URI if provided, otherwise
/// return unmodified.
String _toMultiRootPath(
    Uri fileUri, String? scheme, List<Uri> fileSystemRoots) {
  if (scheme == null || fileSystemRoots.isEmpty || fileUri.scheme != 'file') {
    return fileUri.toString();
  }
  final filePath = fileUri.toFilePath(windows: Platform.isWindows);
  for (final fileSystemRoot in fileSystemRoots) {
    final rootPath = fileSystemRoot.toFilePath(windows: Platform.isWindows);
    if (filePath.startsWith(rootPath)) {
      return '$scheme://${filePath.substring(rootPath.length)}';
    }
  }
  return fileUri.toString();
}
