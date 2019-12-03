// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:dwds/src/debugging/inspector.dart';

import '../utilities/domain.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'metadata.dart';

/// Keeps track of Dart libraries available in the running application.
class LibraryHelper extends Domain {
  /// Map of library ID to [Library].
  final _librariesById = <String, Library>{};

  /// Map of libraryRef ID to [LibraryRef].
  final _libraryRefsById = <String, LibraryRef>{};

  LibraryHelper(AppInspector Function() provider) : super(provider);

  /// Returns all libraryRefs in the app.
  ///
  /// Note this can return a cached result.
  Future<List<LibraryRef>> get libraryRefs async {
    if (_libraryRefsById.isNotEmpty) return _libraryRefsById.values.toList();
    var expression = '''
      (function() {
        $getLibraries
        return libs;
      })()
     ''';
    var result =
        await inspector.remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'contextId': await inspector.contextId,
    });
    handleErrorIfPresent(result, evalContents: expression);
    var libraries = List<String>.from(result.result['result']['value'] as List);
    // Filter out any non-Dart libraries, which basically means the .bootstrap
    // library from build_web_runners.
    var dartLibraries = libraries
        .where((name) => name.startsWith('dart:') || name.endsWith('.dart'));
    for (var library in dartLibraries) {
      var ref = LibraryRef(id: library, name: library, uri: library);
      _libraryRefsById[ref.id] = ref;
    }
    return _libraryRefsById.values.toList();
  }

  Future<Library> libraryFor(LibraryRef libraryRef) async {
    var library = _librariesById[libraryRef.id];
    if (library != null) return library;
    return _librariesById[libraryRef.id] = await _constructLibrary(libraryRef);
  }

  Future<LibraryRef> libraryRefFor(String objectId) async {
    if (_libraryRefsById.isEmpty) await libraryRefs;
    return _libraryRefsById[objectId];
  }

  Future<Library> _constructLibrary(LibraryRef libraryRef) async {
    // Fetch information about all the classes in this library.
    var expression = '''
    (function() {
      ${getLibrarySnippet(libraryRef.uri)}
      var result = {};
      var classes = Object.values(Object.getOwnPropertyDescriptors(library))
        .filter((p) => 'value' in p)
        .map((p) => p.value)
        .filter((l) => l && sdkUtils.isType(l));
      var classList = classes.map(function(clazz) {
        var descriptor = {
          'name': clazz.name,
          'dartName': sdkUtils.typeName(clazz)
        };
        return descriptor;
      });
      result['classes'] = classList;
      return result;
    })()
    ''';
    var result =
        await inspector.remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'contextId': await inspector.contextId,
    });
    handleErrorIfPresent(result, evalContents: expression);
    var classDescriptors = (result.result['result']['value']['classes'] as List)
        .cast<Map<String, Object>>();
    var classRefs = classDescriptors.map<ClassRef>((classDescriptor) {
      var classMetaData = ClassMetaData(
          jsName: classDescriptor['name'],
          libraryId: libraryRef.id,
          dartName: classDescriptor['dartName']);
      return classMetaData.classRef;
    }).toList();
    return Library(
        name: libraryRef.name,
        uri: libraryRef.uri,
        debuggable: true,
        dependencies: [],
        scripts: await inspector.scriptRefs,
        variables: [],
        functions: [],
        classes: classRefs,
        id: libraryRef.id);
  }
}
