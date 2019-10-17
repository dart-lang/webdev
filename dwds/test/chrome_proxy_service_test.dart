// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

final context = TestContext();
ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);
WipConnection get tabConnection => context.tabConnection;

void main() {
  group('shared context', () {
    setUpAll(() async {
      await context.setUp();
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('breakpoints', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;

      setUp(() async {
        vm = await fetchChromeProxyService(context.debugConnection).getVM();
        isolate = await fetchChromeProxyService(context.debugConnection)
            .getIsolate(vm.isolates.first.id);
        scripts = await fetchChromeProxyService(context.debugConnection)
            .getScripts(isolate.id);
        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      test('addBreakpoint', () async {
        // TODO: Much more testing.
        var bp = await service.addBreakpoint(isolate.id, mainScript.id, 23);
        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
        expect(bp.id, isNotNull);
      });

      test('addBreakpoint on a part file', () async {
        var partScript = scripts.scripts
            .firstWhere((script) => script.uri.contains('part.dart'));
        var bp = await service.addBreakpoint(isolate.id, partScript.id, 10);
        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
        expect(bp.id, isNotNull);
      });

      test('addBreakpointAtEntry', () {
        expect(() => service.addBreakpointAtEntry(null, null),
            throwsUnimplementedError);
      });

      test('addBreakpointWithScriptUri', () async {
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, mainScript.uri, 23);
        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
        expect(bp.id, isNotNull);
      });

      test('addBreakpointWithScriptUri absolute file URI', () async {
        var current = context.workingDirectory;
        var _test = path.join(path.dirname(current), '_test');
        var scriptPath = Uri.parse(mainScript.uri).path.substring(1);
        var fullPath = path.join(_test, scriptPath);
        var fileUri = Uri.file(fullPath);
        var bp = await service.addBreakpointWithScriptUri(
            isolate.id, '$fileUri', 23);
        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolate.id, bp.id);
        expect(bp.id, isNotNull);
      });

      test('removeBreakpoint null arguments', () {
        expect(() => service.removeBreakpoint(null, null), throwsArgumentError);
      });

      test("removeBreakpoint doesn't exist", () {
        expect(() => service.removeBreakpoint(isolate.id, '1234'),
            throwsArgumentError);
      });
      test('add and remove breakpoint', () async {
        var bp = await service.addBreakpoint(isolate.id, mainScript.id, 23);
        expect(isolate.breakpoints, [bp]);
        await service.removeBreakpoint(isolate.id, bp.id);
        expect(isolate.breakpoints, isEmpty);
      });
    });

    group('callServiceExtension', () {
      test('success', () async {
        var serviceMethod = 'ext.test.callServiceExtension';
        await tabConnection.runtime
            .evaluate('registerExtension("$serviceMethod");');

        // The non-string keys/values get auto json-encoded to match the vm
        // behavior.
        var args = {
          'bool': true,
          'list': [1, '2', 3],
          'map': {'foo': 'bar'},
          'num': 1.0,
          'string': 'hello',
          1: 2,
          false: true,
        };

        var result =
            await service.callServiceExtension(serviceMethod, args: args);
        expect(
            result.json,
            args.map((k, v) => MapEntry(k is String ? k : jsonEncode(k),
                v is String ? v : jsonEncode(v))));
      }, onPlatform: {
        'windows': const Skip('https://github.com/dart-lang/webdev/issues/711'),
      });

      test('failure', () async {
        var serviceMethod = 'ext.test.callServiceExtensionWithError';
        await tabConnection.runtime
            .evaluate('registerExtensionWithError("$serviceMethod");');

        var errorDetails = {'intentional': 'error'};
        expect(
            service.callServiceExtension(serviceMethod, args: {
              'code': '-32001',
              'details': jsonEncode(errorDetails),
            }),
            throwsA(predicate((error) =>
                error is RPCError &&
                error.code == -32001 &&
                error.details == jsonEncode(errorDetails))));
      }, onPlatform: {
        'windows': const Skip('https://github.com/dart-lang/webdev/issues/711'),
      });
    });

    test('clearVMTimeline', () {
      expect(() => service.clearVMTimeline(), throwsUnimplementedError);
    });

    test('clearVMTimeline', () {
      expect(() => service.clearVMTimeline(), throwsUnimplementedError);
    });

    test('clearVMTimeline', () {
      expect(() => service.clearVMTimeline(), throwsUnimplementedError);
    });

    group('evaluate', () {
      Isolate isolate;
      setUpAll(() async {
        var vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
      });

      group('top level methods', () {
        test('can return strings', () async {
          expect(
              await service.evaluate(
                  isolate.id, isolate.rootLib.id, "helloString('world')"),
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'value', 'world'));
        });

        test('can return bools', () async {
          expect(
              await service.evaluate(
                  isolate.id, isolate.rootLib.id, 'helloBool(true)'),
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString,
                  'valueAsString',
                  'true'));
          expect(
              await service.evaluate(
                  isolate.id, isolate.rootLib.id, 'helloBool(false)'),
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString,
                  'valueAsString',
                  'false'));
        });

        test('can return nums', () async {
          expect(
              await service.evaluate(
                  isolate.id, isolate.rootLib.id, 'helloNum(42.0)'),
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
          expect(
              await service.evaluate(
                  isolate.id, isolate.rootLib.id, 'helloNum(42.2)'),
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString,
                  'valueAsString',
                  '42.2'));
        });

        test('can return objects with ids', () async {
          var object = await service.evaluate(
              isolate.id, isolate.rootLib.id, 'createObject("cool")');
          expect(
              object,
              const TypeMatcher<InstanceRef>()
                  .having((instance) => instance.id, 'id', isNotNull));
          // TODO(jakemac): Add tests for the ClassRef once we create one,
          // https://github.com/dart-lang/sdk/issues/36771.
        });

        group('with provided scope', () {
          Future<InstanceRef> createRemoteObject(String message) async {
            return await service.evaluate(
                    isolate.id, isolate.rootLib.id, 'createObject("$message")')
                as InstanceRef;
          }

          test('single scope object', () async {
            var instance = await createRemoteObject('A');
            var result = await service.evaluate(
                isolate.id, isolate.rootLib.id, 'messageFor(arg1)',
                scope: {'arg1': instance.id});
            expect(
                result,
                const TypeMatcher<InstanceRef>().having(
                    (instance) => instance.valueAsString,
                    'valueAsString',
                    'A'));
          });

          test('multiple scope objects', () async {
            var instance1 = await createRemoteObject('A');
            var instance2 = await createRemoteObject('B');
            var result = await service.evaluate(
                isolate.id, isolate.rootLib.id, 'messagesCombined(arg1, arg2)',
                scope: {'arg1': instance1.id, 'arg2': instance2.id});
            expect(
                result,
                const TypeMatcher<InstanceRef>().having(
                    (instance) => instance.valueAsString,
                    'valueAsString',
                    'AB'));
          });
        });
      });
    });

    test('evaluateInFrame', () {
      expect(() => service.evaluateInFrame(null, null, null),
          throwsUnimplementedError);
    });

    test('getAllocationProfile', () {
      expect(
          () => service.getAllocationProfile(null), throwsUnimplementedError);
    });

    test('getFlagList', () async {
      expect(await service.getFlagList(), isA<FlagList>());
    });

    test('getInstances', () {
      expect(() => service.getInstances(null, null, null),
          throwsUnimplementedError);
    });

    group('getIsolate', () {
      test('works for existing isolates', () async {
        var vm = await service.getVM();
        var result = await service.getIsolate(vm.isolates.first.id);
        expect(result, const TypeMatcher<Isolate>());
        var isolate = result;
        expect(isolate.name, contains(context.appUrl));
        // TODO: library names change with kernel dart-lang/sdk#36736
        expect(isolate.rootLib.uri, endsWith('main.dart'));

        expect(
            isolate.libraries,
            containsAll([
              _libRef('dart:core'),
              _libRef('dart:html'),
              _libRef('package:path/path.dart'),
              // TODO: library names change with kernel dart-lang/sdk#36736
              _libRef(endsWith('main.dart')),
            ]));
        expect(isolate.extensionRPCs, contains('ext.hello_world.existing'));
      });

      test('throws for invalid ids', () async {
        expect(service.getIsolate('bad'), throwsArgumentError);
      });
    });

    group('getObject', () {
      Isolate isolate;
      Library rootLibrary;
      setUpAll(() async {
        var vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        rootLibrary =
            await service.getObject(isolate.id, isolate.rootLib.id) as Library;
      });

      test('Libraries', () async {
        expect(rootLibrary, isNotNull);
        // TODO: library names change with kernel dart-lang/sdk#36736
        expect(rootLibrary.uri, endsWith('main.dart'));
        expect(rootLibrary.classes.length, 1);
        var testClass = rootLibrary.classes.first;
        expect(testClass.name, 'MyTestClass');
      });

      test('Classes', () async {
        var testClass = await service.getObject(
            isolate.id, rootLibrary.classes.first.id) as Class;

        expect(
            testClass.functions,
            unorderedEquals([
              predicate((FuncRef f) => f.name == 'hello' && !f.isStatic),
            ]));
        expect(
            testClass.fields,
            unorderedEquals([
              predicate((FieldRef f) =>
                  f.name == 'message' &&
                  f.declaredType != null &&
                  !f.isStatic &&
                  !f.isConst &&
                  f.isFinal),
              predicate((FieldRef f) =>
                  f.name == 'notFinal' &&
                  f.declaredType != null &&
                  !f.isStatic &&
                  !f.isConst &&
                  !f.isFinal),
            ]));
      });

      test('Strings', () async {
        var worldRef = await service.evaluate(
                isolate.id, isolate.rootLib.id, "helloString('world')")
            as InstanceRef;
        var world =
            await service.getObject(isolate.id, worldRef.id) as Instance;
        expect(world.valueAsString, 'world');
      });

      test('Scripts', () async {
        var scripts = await service.getScripts(isolate.id);
        assert(scripts.scripts.isNotEmpty);
        for (var scriptRef in scripts.scripts) {
          var script =
              await service.getObject(isolate.id, scriptRef.id) as Script;
          var serverPath = DartUri(script.uri, 'hello_world/').serverPath;
          var result =
              await http.get('http://localhost:${context.port}/$serverPath');
          expect(script.source, result.body);
          expect(scriptRef.uri, endsWith('.dart'));
          expect(script.tokenPosTable, isNotEmpty);
        }
      });
    });

    test('getScripts', () async {
      var vm = await service.getVM();
      var isolateId = vm.isolates.first.id;
      var scripts = await service.getScripts(isolateId);
      expect(scripts, isNotNull);
      expect(scripts.scripts.length, greaterThan(0));
      // Test for a known script
      expect(scripts.scripts.map((s) => s.uri),
          contains('package:path/path.dart'));
      // Should return part files as well.
      expect(
          scripts.scripts.map((s) => s.uri), contains(endsWith('part.dart')));
      expect(scripts.scripts.map((s) => s.uri),
          contains('package:intl/src/intl/date_format_helpers.dart'));
    });

    test('clearVMTimeline', () {
      expect(() => service.clearVMTimeline(), throwsUnimplementedError);
    });

    test('getSourceReport', () {
      expect(
          () => service.getSourceReport(null, null), throwsUnimplementedError);
    });

    group('Step', () {
      String isolateId;
      Stream<Event> stream;
      ScriptList scripts;
      ScriptRef mainScript;

      setUp(() async {
        var vm = await service.getVM();
        isolateId = vm.isolates.first.id;
        scripts = await service.getScripts(isolateId);
        await service.streamListen('Debug');
        stream = service.onEvent('Debug');
        mainScript = scripts.scripts
            .firstWhere((script) => script.uri.contains('main.dart'));
        var bp = await service.addBreakpoint(isolateId, mainScript.id, 49);
        // Wait for breakpoint to trigger.
        await stream
            .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);
        await service.removeBreakpoint(isolateId, bp.id);
      });

      tearDown(() async {
        // Resume execution to not impact other tests.
        await service.resume(isolateId);
      });

      test('Into goes to the next Dart location', () async {
        await service.resume(isolateId, step: 'Into');
        // Wait for the step to actually occur.
        await stream
            .firstWhere((event) => event.kind == EventKind.kPauseInterrupted);
        var stack = await service.getStack(isolateId);
        expect(stack, isNotNull);
        var first = stack.frames.first;
        expect(first.kind, 'Regular');
        expect(first.code.kind, 'Dart');
        expect(first.code.name, 'printCount');
      });

      test('Over goes to the next Dart location', () async {
        await service.resume(isolateId, step: 'Over');
        // Wait for the step to actually occur.
        await stream
            .firstWhere((event) => event.kind == EventKind.kPauseInterrupted);
        var stack = await service.getStack(isolateId);
        expect(stack, isNotNull);
        var first = stack.frames.first;
        expect(first.kind, 'Regular');
        expect(first.code.kind, 'Dart');
        expect(first.code.name, '<closure>');
      });

      test('Out goes to the next Dart location', () async {
        await service.resume(isolateId, step: 'Out');
        // Wait for the step to actually occur.
        await stream
            .firstWhere((event) => event.kind == EventKind.kPauseInterrupted);
        var stack = await service.getStack(isolateId);
        expect(stack, isNotNull);
        var first = stack.frames.first;
        expect(first.kind, 'Regular');
        expect(first.code.kind, 'Dart');
        expect(first.code.name, '<closure>');
      });
    });

    group('getStack', () {
      String isolateId;
      Stream<Event> stream;
      ScriptList scripts;
      ScriptRef mainScript;

      setUp(() async {
        var vm = await service.getVM();
        isolateId = vm.isolates.first.id;
        scripts = await service.getScripts(isolateId);
        await service.streamListen('Debug');
        stream = service.onEvent('Debug');
        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      test('returns null if not paused', () async {
        await stream.firstWhere((event) => event.kind == EventKind.kResume);
        expect(await service.getStack(isolateId), isNull);
      });

      /// Support function for pausing and returning the stack at a line.
      Future<Stack> breakAt(int lineNumber) async {
        var bp =
            await service.addBreakpoint(isolateId, mainScript.id, lineNumber);
        // Wait for breakpoint to trigger.
        await stream
            .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);
        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolateId, bp.id);
        var stack = await service.getStack(isolateId);
        // Resume as to not impact other tests.
        await service.resume(isolateId);
        return stack;
      }

      test('returns stack when broken', () async {
        var stack = await breakAt(63);
        expect(stack, isNotNull);
        expect(stack.frames.length, 2);
        var first = stack.frames.first;
        expect(first.kind, 'Regular');
        expect(first.code.kind, 'Dart');
        expect(first.code.name, 'printCount');
      });

      test('stack has a variable', () async {
        var stack = await breakAt(49);
        expect(stack, isNotNull);
        expect(stack.frames.length, 1);
        var first = stack.frames.first;
        expect(first.kind, 'Regular');
        expect(first.code.kind, 'Dart');
        expect(first.code.name, '<closure>');
        // TODO: Make this more precise once this case doesn't
        // also include all the libraries.
        expect(first.vars.length, greaterThanOrEqualTo(1));
        var underscore = first.vars.firstWhere((v) => v.name == '_');
        expect(underscore, isNotNull);
      });

      test('returns non-empty stack when paused', () async {
        await service.pause(isolateId);
        // Wait for pausing to actually propagate.
        await stream
            .firstWhere((event) => event.kind == EventKind.kPauseInterrupted);
        expect(await service.getStack(isolateId), isNotNull);
        // Resume the isolate to not impact other tests.
        await service.resume(isolateId);
      });
    });

    test('getVM', () async {
      var vm = await service.getVM();
      expect(vm.name, isNotNull);
      expect(vm.version, Platform.version);
      expect(vm.isolates.length, equals(1));
      var isolate = vm.isolates.first;
      expect(isolate.id, isNotNull);
      expect(isolate.name, isNotNull);
      expect(isolate.number, isNotNull);
    });

    test('getVersion', () async {
      var version = await service.getVersion();
      expect(version, isNotNull);
      expect(version.major, greaterThan(0));
    });

    group('invoke', () {
      VM vm;
      Isolate isolate;
      InstanceRef testInstance;

      setUp(() async {
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        testInstance = await service.evaluate(
            isolate.id, isolate.rootLib.id, 'myInstance') as InstanceRef;
      });

      test('toString()', () async {
        var remote =
            await service.invoke(isolate.id, testInstance.id, 'toString', []);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString,
                'toString()',
                "Instance of 'MyTestClass'"));
      });

      test('hello()', () async {
        var remote =
            await service.invoke(isolate.id, testInstance.id, 'hello', []);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'hello()', 'world'));
      });

      test('helloString', () async {
        var remote = await service.invoke(isolate.id, isolate.rootLib.id,
            'helloString', ['#StringInstanceRef#abc']);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'helloString', 'abc'));
        expect(
            remote,
            const TypeMatcher<InstanceRef>()
                .having((instance) => instance.kind, 'kind', 'String'));
      });

      test('null argument', () async {
        var remote = await service.invoke(
            isolate.id, isolate.rootLib.id, 'helloString', ['objects/null']);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'helloString', 'null'));
        expect(
            remote,
            const TypeMatcher<InstanceRef>()
                .having((instance) => instance.kind, 'kind', 'Null'));
      });

      test('helloBool', () async {
        var remote = await service.invoke(
            isolate.id, isolate.rootLib.id, 'helloBool', ['objects/bool-true']);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'helloBool', 'true'));
        expect(
            remote,
            const TypeMatcher<InstanceRef>()
                .having((instance) => instance.kind, 'kind', 'Bool'));
      });

      test('helloNum', () async {
        var remote = await service.invoke(
            isolate.id, isolate.rootLib.id, 'helloNum', ['objects/int-123']);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'helloNum', '123'));
        expect(
            remote,
            const TypeMatcher<InstanceRef>()
                .having((instance) => instance.kind, 'kind', 'Double'));
      });

      test('two object arguments', () async {
        var remote = await service.invoke(isolate.id, isolate.rootLib.id,
            'messagesCombined', [testInstance.id, testInstance.id]);
        expect(
            remote,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString,
                'messagesCombined',
                'worldworld'));
        expect(
            remote,
            const TypeMatcher<InstanceRef>()
                .having((instance) => instance.kind, 'kind', 'String'));
      });
    });

    test('kill', () {
      expect(() => service.kill(null), throwsUnimplementedError);
    });

    test('onEvent', () {
      expect(() => service.onEvent(null), throwsUnimplementedError);
    });

    test('pause / resume', () async {
      await service.streamListen('Debug');
      var stream = service.onEvent('Debug');
      var vm = await service.getVM();
      var isolateId = vm.isolates.first.id;
      var pauseCompleter = Completer();
      var pauseSub = tabConnection.debugger.onPaused.listen((_) {
        pauseCompleter.complete();
      });
      var resumeCompleter = Completer();
      var resumeSub = tabConnection.debugger.onResumed.listen((_) {
        resumeCompleter.complete();
      });
      expect(await service.pause(isolateId), const TypeMatcher<Success>());
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseInterrupted);
      expect((await service.getIsolate(isolateId)).pauseEvent.kind,
          EventKind.kPauseInterrupted);
      await pauseCompleter.future;
      expect(await service.resume(isolateId), const TypeMatcher<Success>());
      await stream.firstWhere((event) => event.kind == EventKind.kResume);
      expect((await service.getIsolate(isolateId)).pauseEvent.kind,
          EventKind.kResume);
      await resumeCompleter.future;
      await pauseSub.cancel();
      await resumeSub.cancel();
    });

    test('getInboundReferences', () async {
      expect(() => service.getInboundReferences(null, null, null),
          throwsUnimplementedError);
    });

    test('getRetainingPath', () async {
      expect(() => service.getRetainingPath(null, null, null),
          throwsUnimplementedError);
    });

    test('registerService', () async {
      expect(() => service.registerService('ext.foo.bar', null),
          throwsUnimplementedError);
    });

    test('reloadSources', () {
      expect(() => service.reloadSources(null), throwsUnimplementedError);
    });

    test('setExceptionPauseMode', () async {
      var vm = await service.getVM();
      var isolateId = vm.isolates.first.id;
      expect(await service.setExceptionPauseMode(isolateId, 'all'), _isSuccess);
      expect(await service.setExceptionPauseMode(isolateId, 'unhandled'),
          _isSuccess);
      // Make sure this is the last one - or future tests might hang.
      expect(
          await service.setExceptionPauseMode(isolateId, 'none'), _isSuccess);
      expect(service.setExceptionPauseMode(isolateId, 'invalid'),
          throwsA(isA<ArgumentError>()));
    });

    test('setFlag', () {
      expect(() => service.setFlag(null, null), throwsUnimplementedError);
    });

    test('setLibraryDebuggable', () {
      expect(() => service.setLibraryDebuggable(null, null, null),
          throwsUnimplementedError);
    });

    test('setName', () async {
      var vm = await service.getVM();
      var isolateId = vm.isolates.first.id;
      expect(service.setName(isolateId, 'test'), completion(_isSuccess));
      var isolate = await service.getIsolate(isolateId);
      expect(isolate.name, 'test');
    });

    test('setVMName', () async {
      expect(service.setVMName('foo'), completion(_isSuccess));
      var vm = await service.getVM();
      expect(vm.name, 'foo');
    });

    test('setVMTimelineFlags', () {
      expect(() => service.setVMTimelineFlags(null), throwsUnimplementedError);
    });

    test('streamCancel', () {
      expect(() => service.streamCancel(null), throwsUnimplementedError);
    });

    group('streamListen/onEvent', () {
      group('Debug', () {
        Stream<Event> eventStream;

        setUp(() async {
          expect(await service.streamListen('Debug'),
              const TypeMatcher<Success>());
          eventStream = service.onEvent('Debug');
        });

        test('basic Pause/Resume', () async {
          expect(service.streamListen('Debug'), completion(_isSuccess));
          var stream = service.onEvent('Debug');
          unawaited(tabConnection.debugger.pause());
          await expectLater(
              stream,
              emitsThrough(const TypeMatcher<Event>()
                  .having((e) => e.kind, 'kind', EventKind.kPauseInterrupted)));
          unawaited(tabConnection.debugger.resume());
          expect(
              eventStream,
              emitsThrough(const TypeMatcher<Event>()
                  .having((e) => e.kind, 'kind', EventKind.kResume)));
        });

        test('Inspect', () async {
          expect(
              eventStream,
              emitsThrough(const TypeMatcher<Event>()
                  .having((e) => e.kind, 'kind', EventKind.kInspect)
                  .having(
                      (e) => e.inspectee,
                      'inspectee',
                      const TypeMatcher<InstanceRef>()
                          .having((instance) => instance.id, 'id', isNotNull)
                          .having((instance) => instance.kind, 'inspectee.kind',
                              InstanceKind.kPlainInstance))));
          await tabConnection.runtime.evaluate('inspectInstance()');
        });
      });

      test('Extension', () async {
        expect(service.streamListen('Extension'), completion(_isSuccess));
        var stream = service.onEvent('Extension');
        var eventKind = 'my.custom.event';
        expect(
            stream,
            emitsThrough(predicate((Event event) =>
                event.kind == EventKind.kExtension &&
                event.extensionKind == eventKind &&
                event.extensionData.data['example'] == 'data')));
        await tabConnection.runtime.evaluate("postEvent('$eventKind');");
      });

      test('GC', () async {
        expect(service.streamListen('GC'), completion(_isSuccess));
      });

      group('Isolate', () {
        Stream<Event> isolateEventStream;

        setUp(() async {
          expect(await service.streamListen('Isolate'), _isSuccess);
          isolateEventStream = service.onEvent('Isolate');
        });

        test('ServiceExtensionAdded', () async {
          var extensionMethod = 'ext.foo.bar';
          expect(
              isolateEventStream,
              emitsThrough(predicate((Event event) =>
                  event.kind == EventKind.kServiceExtensionAdded &&
                  event.extensionRPC == extensionMethod)));
          await tabConnection.runtime
              .evaluate("registerExtension('$extensionMethod');");
        });

        test('lifecycle events', () async {
          var vm = await service.getVM();
          var initialIsolateId = vm.isolates.first.id;
          var eventsDone = expectLater(
              isolateEventStream,
              emitsThrough(emitsInOrder([
                predicate((Event event) =>
                    event.kind == EventKind.kIsolateExit &&
                    event.isolate.id == initialIsolateId),
                predicate((Event event) =>
                    event.kind == EventKind.kIsolateStart &&
                    event.isolate.id != initialIsolateId),
                predicate((Event event) =>
                    event.kind == EventKind.kIsolateRunnable &&
                    event.isolate.id != initialIsolateId),
              ])));
          service.destroyIsolate();
          await service.createIsolate(context.appConnection);
          await eventsDone;
          expect((await service.getVM()).isolates.first.id,
              isNot(initialIsolateId));
        });
      });

      test('Timeline', () async {
        expect(service.streamListen('Timeline'), completion(_isSuccess));
      });

      test('Stdout', () async {
        expect(service.streamListen('Stdout'), completion(_isSuccess));
        expect(
            service.onEvent('Stdout'),
            emitsThrough(predicate((Event event) =>
                event.kind == EventKind.kWriteEvent &&
                String.fromCharCodes(base64.decode(event.bytes))
                    .contains('hello'))));
        await tabConnection.runtime.evaluate('console.log("hello");');
      });

      test('Stderr', () async {
        expect(service.streamListen('Stderr'), completion(_isSuccess));
        var stderrStream = service.onEvent('Stderr');
        expect(
            stderrStream,
            emitsThrough(predicate((Event event) =>
                event.kind == EventKind.kWriteEvent &&
                String.fromCharCodes(base64.decode(event.bytes))
                    .contains('Error'))));
        await tabConnection.runtime.evaluate('console.error("Error");');
      });

      test('VM', () async {
        var status = await service.streamListen('VM');
        expect(status, _isSuccess);
        var stream = service.onEvent('VM');
        expect(
            stream,
            emitsThrough(predicate((Event e) =>
                e.kind == EventKind.kVMUpdate && e.vm.name == 'test')));
        await service.setVMName('test');
      });
    });
  });
}

final _isSuccess = isA<Success>();

TypeMatcher _libRef(uriMatcher) =>
    isA<LibraryRef>().having((l) => l.uri, 'uri', uriMatcher);
