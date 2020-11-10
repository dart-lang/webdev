// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pool/pool.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'dart_scope.dart';
import 'debugger.dart';

class FrameComputer {
  final Debugger debugger;

  final _pool = Pool(1);

  final List<WipCallFrame> _callFrames;
  final _computedFrames = <Frame>[];

  var _frameIndex = 0;

  StackTrace _asyncStackTrace;
  List<CallFrame> _asyncFramesToProcess;

  FrameComputer(this.debugger, this._callFrames, {StackTrace asyncStackTrace})
      : _asyncStackTrace = asyncStackTrace;

  /// Given a frame index, return the corresponding JS frame.
  WipCallFrame jsFrameForIndex(int frameIndex) {
    // Clients can send us indices greater than the number of JS frames as async
    // frames don't have corresponding WipCallFrames.
    return frameIndex < _callFrames.length ? _callFrames[frameIndex] : null;
  }

  /// Return the WipScopes for the given JavaScript frame index that are
  /// pertinent for Dart debugging.
  List<WipScope> getWipScopesForFrameIndex(int frameIndex) {
    return filterScopes(jsFrameForIndex(frameIndex));
  }

  /// Translates Chrome callFrames contained in [DebuggerPausedEvent] into Dart
  /// [Frame]s.
  Future<List<Frame>> calculateFrames({int limit}) async {
    return _pool.withResource(() async {
      if (limit != null && _computedFrames.length >= limit) {
        return _computedFrames.take(limit).toList();
      }

      await _collectSyncFrames(limit: limit);
      await _collectAsyncFrames(limit: limit);

      // Remove any trailing kAsyncSuspensionMarker frame.
      if (limit == null &&
          _computedFrames.isNotEmpty &&
          _computedFrames.last.kind == FrameKind.kAsyncSuspensionMarker) {
        _computedFrames.removeLast();
      }

      return _computedFrames;
    });
  }

  Future<void> _collectSyncFrames({int limit}) async {
    if (limit != null && _computedFrames.length == limit) return;

    if (_frameIndex >= _callFrames.length) return;

    final callFrame = _callFrames[_frameIndex];
    var dartFrame =
        await debugger.calculateDartFrameFor(callFrame, _frameIndex++);
    if (dartFrame != null) {
      _computedFrames.add(dartFrame);
    }

    await _collectSyncFrames(limit: limit);
  }

  Future<void> _collectAsyncFrames({int limit}) async {
    if (limit != null && _computedFrames.length == limit) return;

    if (_asyncStackTrace == null) return;

    // We are processing a new set of async frames, add a suspension marker.
    if (_asyncFramesToProcess == null) {
      if (_computedFrames.last?.kind != FrameKind.kAsyncSuspensionMarker) {
        _computedFrames.add(Frame(
            index: _frameIndex++, kind: FrameKind.kAsyncSuspensionMarker));
      }
      _asyncFramesToProcess = _asyncStackTrace.callFrames;
    } else {
      // Process a single async frame.
      if (_asyncFramesToProcess.isNotEmpty) {
        var callFrame = _asyncFramesToProcess.removeAt(0);
        var location = WipLocation.fromValues(
            callFrame.scriptId, callFrame.lineNumber,
            columnNumber: callFrame.columnNumber);
        var tempWipFrame = WipCallFrame({
          'url': callFrame.url,
          'functionName': callFrame.functionName,
          'location': location.json,
          'scopeChain': [],
        });

        var frame = await debugger.calculateDartFrameFor(
          tempWipFrame,
          _frameIndex++,
          populateVariables: false,
        );
        if (frame != null) {
          frame.kind = FrameKind.kAsyncCausal;
          _computedFrames.add(frame);
        }
      }
    }

    // Async frames are no longer on the stack - we don't have local variable
    // information for them.
    if (_asyncFramesToProcess.isEmpty) {
      _asyncStackTrace = _asyncStackTrace.parent;
      _asyncFramesToProcess = null;
    }

    await _collectAsyncFrames(limit: limit);
  }
}
