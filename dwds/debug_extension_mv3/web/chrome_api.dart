// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS()
external Chrome get chrome;

@JS()
@anonymous
class Chrome {
  external Action get action;
}

@JS()
@anonymous
class Action {
  // https://developer.chrome.com/docs/extensions/reference/action/#event-onClicked
  external OnClickedHandler get onClicked;
}

@JS()
@anonymous
class OnClickedHandler {
  external void addListener(void Function(Tab tab) callback);
}

@JS()
@anonymous
class Tab {
  external int get id;
  external String get url;
}
