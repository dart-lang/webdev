// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
import 'dart:async';

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/skip_list.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/batched_expression_evaluator.dart';
import 'package:dwds/src/services/expression_evaluator.dart';

import 'package:test/test.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';
import 'fixtures/fakes.dart';

late ExpressionEvaluator? _evaluator;
late ExpressionEvaluator? _batchedEvaluator;

void main() async {
  group('expression compiler service with fake asset server', () {
    Future<void> stop() async {
      _evaluator?.close();
      _evaluator = null;
      _batchedEvaluator?.close();
      _batchedEvaluator = null;
    }

    setUp(() async {
      globalLoadStrategy = FakeStrategy();

      final assetReader = FakeAssetReader(sourceMap: '');
      final modules = FakeModules();

      final webkitDebugger = FakeWebkitDebugger(scripts: {});
      final pausedController = StreamController<DebuggerPausedEvent>();
      webkitDebugger.onPaused = pausedController.stream;

      final root = 'fakeRoot';
      final entry = 'fake_entrypoint';
      final locations = Locations(assetReader, modules, root);
      locations.initialize(entry);

      final skipLists = SkipLists();
      final debugger = await Debugger.create(
        webkitDebugger,
        (_, __) {},
        locations,
        skipLists,
        root,
      );
      final inspector = FakeInspector(fakeIsolate: simpleIsolate);
      debugger.updateInspector(inspector);

      _evaluator = ExpressionEvaluator(
        entry,
        inspector,
        debugger,
        locations,
        modules,
        FakeExpressionCompiler(),
      );
      _batchedEvaluator = BatchedExpressionEvaluator(
        entry,
        inspector,
        debugger,
        locations,
        modules,
        FakeExpressionCompiler(),
      );
    });

    tearDown(() async {
      await stop();
    });

    group('evaluator', () {
      late ExpressionEvaluator evaluator;

      setUp(() async {
        evaluator = _evaluator!;
      });

      test('can evaluate expression', () async {
        final result =
            await evaluator.evaluateExpression('1', 'main.dart', 'true', {});
        expect(
          result,
          const TypeMatcher<RemoteObject>()
              .having((o) => o.value, 'value', 'true'),
        );
      });

      test('can evaluate expression in frame with null scope', () async {
        // Verify that we don't get the internal error.
        // More extensive testing of 'evaluateExpressionInFrame' is done in
        // evaluation tests for frontend server and build daemon.
        await expectLater(
          evaluator.evaluateExpressionInFrame('1', 0, 'true', null),
          throwsRPCErrorWithMessage(
            'Cannot evaluate on a call frame when the program is not paused',
          ),
        );
      });

      test('can evaluate expression in frame with empty scope', () async {
        // Verify that we don't get the internal error.
        // More extensive testing of 'evaluateExpressionInFrame' is done in
        // evaluation tests for frontend server and build daemon.
        await expectLater(
          evaluator.evaluateExpressionInFrame('1', 0, 'true', {}),
          throwsRPCErrorWithMessage(
            'Cannot evaluate on a call frame when the program is not paused',
          ),
        );
      });

      test('cannot evaluate expression in frame with non-empty scope',
          () async {
        final result = await evaluator
            .evaluateExpressionInFrame('1', 0, 'true', {'a': '1'});
        expect(
          result,
          const TypeMatcher<RemoteObject>()
              .having((o) => o.type, 'type', 'InternalError')
              .having(
                (o) => o.value,
                'value',
                contains(
                  'Using scope for expression evaluation in frame is not supported',
                ),
              ),
        );
      });

      test('returns error if closed', () async {
        evaluator.close();
        final result =
            await evaluator.evaluateExpression('1', 'main.dart', 'true', {});
        expect(
          result,
          const TypeMatcher<RemoteObject>()
              .having((o) => o.type, 'type', 'InternalError')
              .having((o) => o.value, 'value', contains('evaluator closed')),
        );
      });
    });

    group('batched evaluator', () {
      late ExpressionEvaluator evaluator;

      setUp(() async {
        evaluator = _batchedEvaluator!;
      });

      test('can evaluate expression', () async {
        final result =
            await evaluator.evaluateExpression('1', 'main.dart', 'true', {});
        expect(
          result,
          const TypeMatcher<RemoteObject>()
              .having((o) => o.value, 'value', 'true'),
        );
      });

      test('returns error if closed', () async {
        evaluator.close();
        final result =
            await evaluator.evaluateExpression('1', 'main.dart', 'true', {});
        expect(
          result,
          const TypeMatcher<RemoteObject>()
              .having((o) => o.type, 'type', 'InternalError')
              .having((o) => o.value, 'value', contains('evaluator closed')),
        );
      });
    });
  });
}
