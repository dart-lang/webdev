// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

int valueFromTestLibrary= 3;

int testLibraryFunction(int formal) {
  return formal; // Breakpoint: testLibraryFunction
}

class ClassFromPackage {
  final int field;
  final int _field;
  ClassFromPackage(this.field, this._field) {
    print('Contructor'); // Breakpoint: testLibraryConstructor
  }

  @override
  String toString() => 'field: $field, _field: $_field';
}
