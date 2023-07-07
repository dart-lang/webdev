// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/metadata/class.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// Keeps track of Dart classes available in the running application.
class ClassHelper extends Domain {
  final _logger = Logger('ClassHelper');

  /// Map of class ID to [Class].
  final _classes = <String, Class>{};

  ClassHelper(AppInspectorInterface appInspector) {
    inspector = appInspector;
    final staticClasses = [
      classRefForClosure,
      classRefForString,
      classRefForUnknown,
    ];
    for (var classRef in staticClasses) {
      final classId = classRef.id;
      if (classId != null) {
        _classes[classId] = Class(
          name: classRef.name,
          isAbstract: false,
          isConst: false,
          library: null,
          interfaces: [],
          fields: [],
          functions: [],
          subclasses: [],
          id: classId,
          traceAllocations: false,
        );
      }
    }
  }

  /// Returns the [Class] that corresponds to the provided [objectId].
  ///
  /// If a corresponding class does not exist it will return null.
  Future<Class?> forObjectId(String objectId) async {
    if (!objectId.startsWith('classes|')) return null;
    var clazz = _classes[objectId];
    if (clazz != null) return clazz;
    final splitId = objectId.split('|');
    final libraryId = splitId[1];
    if (libraryId == 'null') {
      throw UnsupportedError('unknown library: $libraryId');
    }
    final libraryRef = await inspector.libraryRefFor(libraryId);
    if (libraryRef == null) {
      throw Exception('Could not find library: $libraryId');
    }
    final classRef = classRefFor(libraryId, splitId.last);
    clazz = await _constructClass(libraryRef, classRef);
    if (clazz == null) {
      throw Exception('Could not contruct class: $classRef');
    }
    return _classes[objectId] = clazz;
  }

  /// Constructs a [Class] instance for the provided [LibraryRef] and
  /// [ClassRef].
  Future<Class?> _constructClass(
    LibraryRef libraryRef,
    ClassRef classRef,
  ) async {
    final libraryUri = libraryRef.uri;
    final className = classRef.name;
    final classId = classRef.id;

    if (libraryUri == null || classId == null || className == null) return null;

    final expression = '''
      (function() {
        const sdk = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk');
        const dart = sdk.dart;
        return dart.getClassMetadata('$libraryUri', '$className');
      })()
    ''';

    RemoteObject result;
    try {
      result = await inspector.remoteDebugger.evaluate(
        expression,
        returnByValue: true,
        contextId: await inspector.contextId,
      );
    } on ExceptionDetails catch (e) {
      throw ChromeDebugException(e.json, evalContents: expression);
    }

    _logger.fine('Class info: ${result.json}');

    final classDescriptor = result.value as Map<String, dynamic>;
    final methodRefs = <FuncRef>[];
    final methodDescriptors =
        classDescriptor['methods'] as Map<String, dynamic>;
    //final staticMethodDescriptors =
    //    classDescriptor['staticMethods'] as Map<String, dynamic>;
    //methodDescriptors.addAll(staticMethodDescriptors);
    methodDescriptors.forEach((name, descriptor) {
      final methodId = 'methods|$classId|$name';
      methodRefs.add(
        FuncRef(
          id: methodId,
          name: name,
          owner: classRef,
          isConst: descriptor['isConst'] as bool,
          isStatic: descriptor['isStatic'] as bool,
          // TODO(annagrin): get information about getters and setters from symbols.
          // https://github.com/dart-lang/sdk/issues/46723
          implicit: false,
        ),
      );
    });
    final fieldRefs = <FieldRef>[];
    final fieldDescriptors = classDescriptor['fields'] as Map<String, dynamic>;
    fieldDescriptors.forEach((name, descriptor) {
      final classMetaData = descriptor.containsKey('classRefLibraryId') &&
              descriptor.containsKey('classRefDartName')
          ? ClassMetaData(
              runtimeKind: RuntimeObjectKind.type,
              classRef: classRefFor(
                descriptor['classRefLibraryId'],
                descriptor['classRefDartName'],
              ),
            )
          : _classMetadataForUnknown;

      fieldRefs.add(
        FieldRef(
          name: name,
          owner: classRef,
          declaredType: InstanceRef(
            identityHashCode: createId().hashCode,
            id: createId(),
            kind: classMetaData.kind,
            classRef: classMetaData.classRef,
          ),
          isConst: descriptor['isConst'] as bool,
          isFinal: descriptor['isFinal'] as bool,
          isStatic: descriptor['isStatic'] as bool,
          id: createId(),
        ),
      );
    });
/*
    final staticFieldDescriptors =
        classDescriptor['staticFields'] as Map<String, dynamic>;
    staticFieldDescriptors.forEach((name, descriptor) {
      fieldRefs.add(
        FieldRef(
          name: name,
          owner: classRef,
          declaredType: InstanceRef(
            identityHashCode: createId().hashCode,
            id: createId(),
            kind: InstanceKind.kType,
            classRef: classRef,
          ),
          isConst: descriptor['isConst'] as bool,
          isFinal: descriptor['isFinal'] as bool,
          isStatic: descriptor['isStatic'] as bool,
          id: createId(),
        ),
      );
    });*/

    // TODO: Implement the rest of these
    // https://github.com/dart-lang/webdev/issues/176.
    return Class(
      name: classRef.name,
      isAbstract: false,
      isConst: false,
      library: libraryRef,
      interfaces: [],
      fields: fieldRefs,
      functions: methodRefs,
      subclasses: [],
      id: classId,
      traceAllocations: false,
    );
  }
}

final _classMetadataForUnknown = ClassMetaData(
  runtimeKind: RuntimeObjectKind.object,
  classRef: classRefForUnknown,
);
