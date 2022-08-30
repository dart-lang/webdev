// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS()
external Console get console;

@JS()
// ignore: non_constant_identifier_names
external Json get JSON;

@JS()
@anonymous
class Console {
  external void log(String header,
      [String style1, String style2, String style3]);
}

@JS()
@anonymous
class Json {
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify
  external String stringify(o);
}
