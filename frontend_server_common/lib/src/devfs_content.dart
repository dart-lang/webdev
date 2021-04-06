// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

// Note: this is a copy from flutter tools, updated to work with dwds tests

import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';

import 'utilities.dart';

/// Common superclass for content copied to the device.
abstract class DevFSContent {
  /// Return true if this is the first time this method is called
  /// or if the entry has been modified since this method was last called.
  bool get isModified;

  /// Return true if this is the first time this method is called
  /// or if the entry has been modified after the given time
  /// or if the given time is null.
  bool isModifiedAfter(DateTime time);

  int get size;

  Future<List<int>> contentsAsBytes();

  Stream<List<int>> contentsAsStream();

  /// Return the list of files this content depends on.
  List<String> get fileDependencies => <String>[];
}

// File content to be copied to the device.
class DevFSFileContent extends DevFSContent {
  DevFSFileContent(this.file);

  final FileSystemEntity file;
  File _linkTarget;
  FileStat _fileStat;

  File _getFile() {
    if (_linkTarget != null) {
      return _linkTarget;
    }
    if (file is Link) {
      // The link target.
      return fileSystem.file(file.resolveSymbolicLinksSync());
    }
    return file as File;
  }

  void _stat() {
    if (_linkTarget != null) {
      // Stat the cached symlink target.
      var fileStat = _linkTarget.statSync();
      if (fileStat.type == FileSystemEntityType.notFound) {
        _linkTarget = null;
      } else {
        _fileStat = fileStat;
        return;
      }
    }
    var fileStat = file.statSync();
    _fileStat =
        fileStat.type == FileSystemEntityType.notFound ? null : fileStat;
    if (_fileStat != null && _fileStat.type == FileSystemEntityType.link) {
      // Resolve, stat the symlink target.
      var resolved = file.resolveSymbolicLinksSync();
      var linkTarget = fileSystem.file(resolved);
      // Stat the link target.
      var fileStat = linkTarget.statSync();
      if (fileStat.type == FileSystemEntityType.notFound) {
        _fileStat = null;
        _linkTarget = null;
      }
    }
    if (_fileStat == null) {
      printError(
          'Unable to get status of file "${file.path}": file not found.');
    }
  }

  @override
  List<String> get fileDependencies => <String>[_getFile().path];

  @override
  bool get isModified {
    var _oldFileStat = _fileStat;
    _stat();
    if (_oldFileStat == null && _fileStat == null) {
      return false;
    }
    return _oldFileStat == null ||
        _fileStat == null ||
        _fileStat.modified.isAfter(_oldFileStat.modified);
  }

  @override
  bool isModifiedAfter(DateTime time) {
    var _oldFileStat = _fileStat;
    _stat();
    if (_oldFileStat == null && _fileStat == null) {
      return false;
    }
    return time == null ||
        _oldFileStat == null ||
        _fileStat == null ||
        _fileStat.modified.isAfter(time);
  }

  @override
  int get size {
    if (_fileStat == null) {
      _stat();
    }
    // Can still be null if the file wasn't found.
    return _fileStat?.size ?? 0;
  }

  @override
  Future<List<int>> contentsAsBytes() => _getFile().readAsBytes();

  @override
  Stream<List<int>> contentsAsStream() => _getFile().openRead();
}

/// Byte content to be copied to the device.
class DevFSByteContent extends DevFSContent {
  DevFSByteContent(this._bytes);

  List<int> _bytes;

  bool _isModified = true;
  DateTime _modificationTime = DateTime.now();

  List<int> get bytes => _bytes;

  set bytes(List<int> value) {
    _bytes = value;
    _isModified = true;
    _modificationTime = DateTime.now();
  }

  /// Return true only once so that the content is written to the device only once.
  @override
  bool get isModified {
    var modified = _isModified;
    _isModified = false;
    return modified;
  }

  @override
  bool isModifiedAfter(DateTime time) {
    return time == null || _modificationTime.isAfter(time);
  }

  @override
  int get size => _bytes.length;

  @override
  Future<List<int>> contentsAsBytes() async => _bytes;

  @override
  Stream<List<int>> contentsAsStream() =>
      Stream<List<int>>.fromIterable(<List<int>>[_bytes]);
}

/// String content to be copied to the device.
class DevFSStringContent extends DevFSByteContent {
  DevFSStringContent(String string)
      : _string = string,
        super(utf8.encode(string));

  String _string;

  String get string => _string;

  set string(String value) {
    _string = value;
    super.bytes = utf8.encode(_string);
  }

  @override
  set bytes(List<int> value) {
    string = utf8.decode(value);
  }
}

// Basic statistics for DevFS update operation.
class UpdateFSReport {
  UpdateFSReport({
    bool success = false,
    int invalidatedSourcesCount = 0,
    int syncedBytes = 0,
  }) {
    _success = success;
    _invalidatedSourcesCount = invalidatedSourcesCount;
    _syncedBytes = syncedBytes;
  }

  bool get success => _success;
  int get invalidatedSourcesCount => _invalidatedSourcesCount;
  int get syncedBytes => _syncedBytes;

  /// JavaScript modules produced by the incremental compiler in `dartdevc`
  /// mode.
  ///
  /// Only used for JavaScript compilation.
  List<String> invalidatedModules;

  void incorporateResults(UpdateFSReport report) {
    if (!report._success) {
      _success = false;
    }
    _invalidatedSourcesCount += report._invalidatedSourcesCount;
    _syncedBytes += report._syncedBytes;
    invalidatedModules ??= report.invalidatedModules;
  }

  bool _success;
  int _invalidatedSourcesCount;
  int _syncedBytes;
}
