// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library require_reloading_manager;

import 'dart:js_interop';

import 'package:js/js.dart';
import 'package:web/helpers.dart';

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
  @JS()
  external V? get(K key);

  @JS()
  external Object keys();

  @JS()
  external Object values();
}

extension ObjectValues on JSObject {
  Iterable<Object?> get values => _jsObjectValues(this).toDartIterable();
}

extension JSArrayToIterable on JSArray {
  Iterable<T> toDartIterable<T>() => toDart.map((e) => e.dartify() as T);
}

extension JSMapToMap<K, V> on JsMap<K, V> {
  Iterable<K> get dartKeys => _jsArrayFrom(keys()).toDartIterable<K>();
}

extension NodeListExtension on NodeList {
  external void forEach(JSFunction callback);
}
