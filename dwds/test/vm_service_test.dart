// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@TestOn('vm')
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

//import 'package:vm_service/vm_service_io.dart';

import 'fixtures/context.dart';
import 'fixtures/logging.dart';

class TestSetup {
  static final contextUnsound = TestContext(
      directory: p.join('..', 'fixtures', '_testPackage'),
      entry: p.join('..', 'fixtures', '_testPackage', 'web', 'main.dart'),
      path: 'index.html',
      pathToServe: 'web');

  TestContext context;

  TestSetup.unsound() : context = contextUnsound;
}

void main() {
  group('shared context |', () {
    // Enable verbose logging for debugging.
    var debug = false;

    var setup = TestSetup.unsound();
    var context = setup.context;

    StreamController<String> output;
    WebSocket socket;
    VmService vmService;
    Stream<Event> debugStream;
    IsolateRef isolate;
    Script mainScript;
            
    setUpAll(() async {
      // redirect logs for testing
      output = StreamController<String>.broadcast()
        ..stream.listen(debug? print: printOnFailure);

      void logWriter(Level level, String message,
              {String error, String loggerName, String stackTrace}) =>
          output.add('[$level] $loggerName: $message');

      configureLogWriter(customLogWriter: logWriter);

      // Wait for debug service Uri
      String wsUri;
      var findWsUri = expectLater(output.stream, emitsThrough((message) {
        wsUri = _getDebugServiceUri(message as String);
        return wsUri != null;
      }));
      
      await context.setUp(verboseCompiler: debug);
      await findWsUri;

      await Chain.capture(() async {
        socket = await WebSocket.connect(wsUri);
        vmService = await _vmServiceConnectUri(socket);
        }, onError: (e,s) {
          print('AsyncError: $e:$s');
        });
      
      await vmService.streamListen('Debug');
      debugStream = vmService.onEvent('Debug');

      var vm = await vmService.getVM();
      isolate = vm.isolates.first;
      var scripts = await vmService.getScripts(isolate.id);
      var mainScriptRef = scripts.scripts
          .firstWhere((each) => each.uri.contains('main.dart'));
      mainScript =
          await vmService.getObject(isolate.id, mainScriptRef.id) as Script;
    });

    tearDownAll(() async {
      await vmService?.dispose();
      await context.tearDown();
    });

    Future<void> onBreakPoint(
        String bpId, Script script, Future<void> Function() body) async {
      Breakpoint bp;
      try {
        var line = await _findBreakpointLine(bpId, isolate.id, mainScript);
        bp = await vmService.addBreakpointWithScriptUri(
            isolate.id, script.uri, line);

        expect(bp, isNotNull);

        await debugStream.firstWhere(
            (Event event) => event.kind == EventKind.kPauseBreakpoint);

        await body();
      } finally {
        // Remove breakpoint so it doesn't impact other tests or retries.
        if (bp != null) {
          await vmService.removeBreakpoint(isolate.id, bp.id);
        }
      }
    }

    group('callStack |', () {

      test('callstack while paused', () async {
        await onBreakPoint('printLocal', mainScript, () async {
          var stack = await vmService.getStack(isolate.id, limit: 1);
          expect(stack, isNotNull);
        });
        await vmService.resume(isolate.id);
      });

      test('callstack while paused in parallel', () async {
        await onBreakPoint('printLocal', mainScript, () async {
          var futures = [
            vmService.getStack(isolate.id, limit: 1), 
            vmService.getStack(isolate.id, limit: 1),
            vmService.getStack(isolate.id, limit: 1),
            vmService.getStack(isolate.id, limit: 1),
          ];
          await Future.wait(futures.map((e) => expectLater(e, isNotNull)));
        });
        await vmService.resume(isolate.id);
      });

      test('callstack while running', () async {
        await expectLater(vmService.getStack(isolate.id, limit: 1), throwsRPCError);
      });

      test('callstack on incorrect isolate', () async {
        await expectLater(vmService.getStack('bad', limit: 1), throwsRPCError);
      });

      test('callstack while running in parallel', () async {
        var futures = [
          vmService.getStack(isolate.id, limit: 1),
          vmService.getStack(isolate.id, limit: 1),
          vmService.getStack(isolate.id, limit: 1),
          vmService.getStack(isolate.id, limit: 1),
        ];
        await Future.wait(futures.map((e) => expectLater(e, throwsRPCError)));
      });

      test('callstack while running in parallel with a broken socket', () async {
        var futures = [
          () async { socket.addError('error', StackTrace.current); throw RPCError('', 0, ''); },
          vmService.getStack(isolate.id, limit: 1),
          vmService.getStack(isolate.id, limit: 1),
          vmService.getStack(isolate.id, limit: 1),
          vmService.getStack(isolate.id, limit: 1),
        ];
        await Future.wait(futures.map((e) => expectLater(e, throwsRPCError)));
      });
    });
  }, timeout: const Timeout.factor(2), retry: 0);
}

Future<int> _findBreakpointLine(
    String breakpointId, String isolateId, Script script) async {
  var lines = LineSplitter.split(script.source).toList();
  var lineNumber =
      lines.indexWhere((l) => l.endsWith('// Breakpoint: $breakpointId'));
  if (lineNumber == -1) {
    throw StateError('Unable to find breakpoint in ${script.uri} with id '
        '$breakpointId');
  }
  return lineNumber + 1;
}

/// Connect to the given uri and return a new [VmService] instance.
Future<VmService> _vmServiceConnectUri(WebSocket socket) async {
  final controller = StreamController();
  final streamClosedCompleter = Completer();

  socket.listen(
    controller.add,
    onDone: streamClosedCompleter.complete,
  );

  return VmService(
    controller.stream,
    socket.add,
    log: null,
    disposeHandler: socket.close,
    streamClosed: streamClosedCompleter.future,
  );
}

String _getDebugServiceUri(String line) {
  var regex = RegExp(r'Debug service listening on (?<wsUri>[^\s^\\]*)');
  var match = regex.firstMatch(line);
  if (match != null) {
    var wsUri = match.namedGroup('wsUri');
    return wsUri;
  }
  return null;
}
