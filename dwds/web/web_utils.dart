// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library require_reloading_manager;

import 'dart:js_interop';

import 'package:js/js.dart';

@JS('Array.from')
external JSArray _jsArrayFrom(Object any);

@JS('Object.values')
external JSArray _jsObjectValues(Object any);

@JS('Error')
abstract class JsError {
  @JS()
  external String get message;

  @JS()
  external String get stack;
}

@JS('Map')
abstract class JsMap<K, V> {
  @JS('Map.get')
  external V? get(K key);

  @JS()
  external Object keys();
}

extension ObjectExtension on JSObject {
  Iterable<Object?> get values => _jsObjectValues(this).toDartIterable();
}

extension JSArrayExtension on JSArray {
  Iterable<T> toDartIterable<T>() => toDart.map((e) => e.dartify() as T);
  List<T> toDartList<T>() => toDartIterable<T>().toList();
}

extension ModuleDependencyGraph on JsMap<String, List<String>> {
  Iterable<String> get modules => _jsArrayFrom(keys()).toDartIterable<String>();

  List<String> parents(String key) =>
      (get(key) as JSArray?)?.toDartList<String>() ?? [];
}
