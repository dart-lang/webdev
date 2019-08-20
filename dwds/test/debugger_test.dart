// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:source_maps/parser.dart';
import 'package:test/test.dart';

import 'fixtures/context.dart';
import 'fixtures/debugger_data.dart';
import 'fixtures/fakes.dart';

final context = TestContext();
AppInspector inspector;
Debugger debugger;
FakeWebkitDebugger webkitDebugger;

void main() async {
  setUpAll(() async {
    webkitDebugger = FakeWebkitDebugger();
    debugger = await Debugger.create(
      null,
      webkitDebugger,
      null,
      () => inspector,
      'fakeRoot',
      (level, message) {
        printOnFailure('[$level]: $message');
      },
      context.moduleStrategy,
    );
    inspector = FakeInspector();
  });

  /// Test that we get expected variable values from a hard-coded
  /// stack frame.
  test('frames 1', () async {
    // TODO: Generalize this and make it clearer and easier to test
    // different cases.

    // Target entry for Dart source line 12 (zero-based), column 0
    var entry = TargetEntry(0, 0, 12, 0, 0);

    // Entries for the JS line 92 (zero-based), with just one actual entry
    var lineEntry = TargetLineEntry(92, [entry]);
    var location = Location.from(
      'foo.dart',
      lineEntry,
      entry,
      DartUri('package:foo/foo.dart'),
    );
    // Create a single location in the JS script the location in our hard-coded
    // frame.
    debugger.sources.noteLocation('dart', location, '69');

    var frames = await debugger.dartFramesFor(frames1);
    expect(frames, isNotNull);
    var firstFrame = frames[0];
    var frame1Variables = firstFrame.vars.map((each) => each.name).toList();
    expect(frame1Variables, ['a', 'b']);
  });
}
