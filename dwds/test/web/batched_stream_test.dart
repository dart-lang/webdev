// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@Retry(0)

import 'dart:async';

import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

import '../../web/batched_stream.dart';

void main() {
  group('Batched stream controller', () {
    test('Emits batches', () async {
      const size = 100;
      const delay = Duration(milliseconds: 1000);

      var batchOne = List<int>.generate(size, (index) => index);
      var batchTwo = List<int>.generate(size, (index) => size + index);
      var inputController = StreamController<int>();

      // Setup controller.
      var controller = BatchedStreamController<int>(delay: 500);

      // Setup output listener.
      var outputEmitted = expectLater(
          controller.stream,
          emitsInOrder([
            batchOne,
            batchTwo,
          ]));

      // Setup input.
      var inputAdded = controller.sink.addStream(inputController.stream);

      // Add input.
      batchOne.forEach(inputController.sink.add);
      await Future.delayed(delay);
      batchTwo.forEach(inputController.sink.add);
      await inputController.sink.close();

      // Wait for input to finish.
      await inputAdded;
      await controller.close();

      // Verify the output.
      await outputEmitted;
    });

    test('Emits all inputs in order', () async {
      const size = 10;
      const delay = Duration(milliseconds: 200);

      var input = List<int>.generate(size, (index) => index);
      var inputController = StreamController<int>();

      // Setup controller.
      var controller = BatchedStreamController<int>(delay: 500);

      // Setup output listener.
      var output = controller.stream.toList();

      // Setup input.
      var inputAdded = controller.sink.addStream(inputController.stream);

      // Add input.
      for (var e in input) {
        inputController.sink.add(e);
        await Future.delayed(delay);
      }
      await inputController.sink.close();

      // Wait for input to finish.
      await inputAdded;
      await controller.close();

      // Verify the output.
      var result = await output;
      expect(result.length, greaterThan(1));

      var flattened = <int>[];
      result.forEach(flattened.addAll);
      expect(flattened, input);
    });
  });
}
