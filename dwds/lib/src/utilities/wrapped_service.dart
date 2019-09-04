// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

export 'package:vm_service/vm_service.dart'
    hide
        LibraryRef,
        Library,
        Script,
        ScriptRef,
        Isolate,
        IsolateRef,
        ClassRef,
        Class,
        Instance,
        InstanceRef,
        FuncRef;

class FuncRef extends vm_service.FuncRef {
  FuncRef._();

  factory FuncRef({
    @required String name,
    @required owner,
    @required bool isStatic,
    @required bool isConst,
    @required String id,
  }) {
    var funcRef = FuncRef._();
    funcRef
      ..name = name
      ..owner = owner
      ..isStatic = isStatic
      ..isConst = isConst
      ..id = id;
    return funcRef;
  }
}

class IsolateRef extends vm_service.IsolateRef {
  IsolateRef._();

  factory IsolateRef({
    @required String number,
    @required String name,
    @required String id,
  }) {
    var isolateRef = IsolateRef._();
    isolateRef
      ..number = number
      ..name = name
      ..id = id;
    return isolateRef;
  }
}

class Isolate extends vm_service.Isolate {
  Isolate._();

  factory Isolate({
    @required String number,
    @required String name,
    @required int startTime,
    @required bool runnable,
    @required int livePorts,
    @required bool pauseOnExit,
    @required vm_service.Event pauseEvent,
    @required List<vm_service.LibraryRef> libraries,
    @required List<vm_service.Breakpoint> breakpoints,
    @required String exceptionPauseMode,
    @required String id,
  }) {
    var isolate = Isolate._();
    isolate
      ..number = number
      ..startTime = startTime
      ..runnable = runnable
      ..livePorts = livePorts
      ..pauseOnExit = pauseOnExit
      ..pauseEvent = pauseEvent
      ..libraries = libraries
      ..breakpoints = breakpoints
      ..exceptionPauseMode = exceptionPauseMode
      ..name = name
      ..id = id;
    return isolate;
  }
}

class ClassRef extends vm_service.ClassRef {
  ClassRef._();

  factory ClassRef({
    @required String name,
    @required String id,
  }) {
    var classRef = ClassRef._();
    classRef
      ..name = name
      ..id = id;
    return classRef;
  }
}

class Class extends vm_service.Class {
  Class._();

  factory Class({
    @required String name,
    @required bool isAbstract,
    @required bool isConst,
    @required LibraryRef library,
    @required List<vm_service.InstanceRef> interfaces,
    @required List<vm_service.FieldRef> fields,
    @required List<vm_service.FuncRef> functions,
    @required List<vm_service.ClassRef> subclasses,
    @required String id,
  }) {
    var classs = Class._();
    classs
      ..name = name
      ..isAbstract = isAbstract
      ..isConst = isConst
      ..library = library
      ..interfaces = interfaces
      ..fields = fields
      ..functions = functions
      ..subclasses = subclasses
      ..id = id;
    return classs;
  }
}

class InstanceRef extends vm_service.InstanceRef {
  InstanceRef._();

  factory InstanceRef({
    @required String kind,
    @required vm_service.ClassRef classRef,
    @required String id,
  }) {
    var instanceRef = InstanceRef._();
    instanceRef
      ..kind = kind
      ..classRef = classRef
      ..id = id;
    return instanceRef;
  }
}

class Instance extends vm_service.Instance {
  Instance._();

  factory Instance({
    @required String kind,
    @required vm_service.ClassRef classRef,
    @required String id,
  }) {
    var instance = Instance._();
    instance
      ..kind = kind
      ..classRef = classRef
      ..id = id;
    return instance;
  }
}

class LibraryRef extends vm_service.LibraryRef {
  LibraryRef._();

  factory LibraryRef({
    @required String name,
    @required String uri,
    @required String id,
  }) {
    var libraryRef = LibraryRef._();
    libraryRef
      ..name = name
      ..uri = uri
      ..id = id;
    return libraryRef;
  }
}

class Library extends vm_service.Library {
  Library._();

  factory Library({
    @required String name,
    @required String uri,
    @required bool debuggable,
    @required List<vm_service.LibraryDependency> dependencies,
    @required List<vm_service.ScriptRef> scripts,
    @required List<vm_service.FieldRef> variables,
    @required List<vm_service.FuncRef> functions,
    @required List<vm_service.ClassRef> classes,
    @required String id,
  }) {
    var library = Library._();
    library
      ..name = name
      ..uri = uri
      ..debuggable = debuggable
      ..dependencies = dependencies
      ..scripts = scripts
      ..variables = variables
      ..functions = functions
      ..classes = classes
      ..id = id;
    return library;
  }
}

class Script extends vm_service.Script {
  Script._();

  factory Script({
    @required String uri,
    @required vm_service.LibraryRef library,
    @required String id,
  }) {
    var script = Script._();
    script
      ..uri = uri
      ..library = library
      ..id = id;
    return script;
  }
}

class ScriptRef extends vm_service.ScriptRef {
  ScriptRef._();

  factory ScriptRef({
    @required String uri,
    @required String id,
  }) {
    var scriptRef = ScriptRef._();
    scriptRef
      ..uri = uri
      ..id = id;
    return scriptRef;
  }
}
