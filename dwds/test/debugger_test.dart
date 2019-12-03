// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:async';

import 'package:dwds/dwds.dart' show ModuleStrategy;
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/evaluation_context.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:source_maps/parser.dart';
import 'package:test/test.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart'
    show DebuggerPausedEvent;

import 'fixtures/context.dart';
import 'fixtures/debugger_data.dart';
import 'fixtures/fakes.dart';

final context = TestContext();
AppInspector inspector;
Debugger debugger;
FakeWebkitDebugger webkitDebugger;
StreamController<DebuggerPausedEvent> pausedController;
Locations locations;

void main() async {
  setUpAll(() async {
    globalModuleStrategy = ModuleStrategy.requireJS;
    webkitDebugger = FakeWebkitDebugger();
    pausedController = StreamController<DebuggerPausedEvent>();
    webkitDebugger.onPaused = pausedController.stream;
    var root = 'fakeRoot';
    var modules = Modules(webkitDebugger, root, null);
    locations = Locations(null, modules, root);
    debugger = await Debugger.create(
      webkitDebugger,
      null,
      () => inspector,
      null,
      null,
      locations,
      root,
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
    locations.noteLocation('dart', location, '69');

    var frames = await debugger.dartFramesFor(frames1);
    expect(frames, isNotNull);
    var firstFrame = frames[0];
    var frame1Variables = firstFrame.vars.map((each) => each.name).toList();
    expect(frame1Variables, ['a', 'b']);
  });

  group('errors', () {
    setUp(() {
      // We need to provide an Isolate so that the code doesn't bail out on a null
      // check before it has a chance to throw.
      inspector = FakeInspector(fakeIsolate: simpleIsolate);
    });

    test('errors in the zone are caught and logged', () async {
      // Add a DebuggerPausedEvent with a null parameter to provoke an error.
      pausedController.sink.add(DebuggerPausedEvent(null));
      expect(
          Debugger.logger.onRecord,
          emitsThrough(predicate(
              (log) => log.message == 'Error handling Chrome event')));
    });
  });
}
