// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart'
    hide StackTrace;

import '../utilities/wrapped_service.dart';
import 'dart_scope.dart';
import 'debugger.dart';

class FrameComputer {
  final Debugger debugger;

  final List<WipCallFrame> _callFrames;

  FrameComputer(this.debugger, this._callFrames);

  /// Given a frame index, return the corresponding JS frame.
  WipCallFrame jsFrameForIndex(int frameIndex) {
    return _callFrames[frameIndex];
  }

  /// Return the WipScopes for the given JavaScript frame index that are
  /// pertinent for Dart debugging.
  List<WipScope> getWipScopesForFrameIndex(int frameIndex) {
    return filterScopes(jsFrameForIndex(frameIndex));
  }

  /// Returns the top Dart frame for the Chrome callFrames contained in a
  /// [DebuggerPausedEvent].
  ///
  /// This will return null if there are no suitable frames.
  Future<Frame> calculateTopFrame() async {
    for (var frameIndex = 0; frameIndex < _callFrames.length; frameIndex++) {
      final callFrame = _callFrames[frameIndex];
      var dartFrame =
          await debugger.calculateDartFrameFor(callFrame, frameIndex);
      if (dartFrame != null) {
        return dartFrame;
      }
    }
    return null;
  }

  /// Translates Chrome callFrames contained in [DebuggerPausedEvent] into Dart
  /// [Frame]s.
  Future<List<Frame>> calculateFrames() async {
    // TODO: Investigate the use of package:pool to request information for ~6
    // frames at a time.

    var dartFrames = <Frame>[];

    // Here, we continue to increment the dart frame index even if we don't
    // create a dart frame; this lets the dart frame index match the javascript
    // ones.
    for (var frameIndex = 0; frameIndex < _callFrames.length; frameIndex++) {
      final callFrame = _callFrames[frameIndex];
      var dartFrame =
          await debugger.calculateDartFrameFor(callFrame, frameIndex);
      if (dartFrame != null) {
        dartFrames.add(dartFrame);
      }
    }

    return dartFrames;
  }
}
