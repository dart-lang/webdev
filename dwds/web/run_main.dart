// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:js_interop';
import 'package:web/helpers.dart';

import 'web_utils.dart';

// According to the CSP3 spec a nonce must be a valid base64 string.
final _noncePattern = RegExp('^[\\w+/_-]+[=]{0,2}\$');

/// Returns CSP nonce, if set for any script tag.
String? _findNonce() {
  final elements = window.document.querySelectorAll('script');
  elements.forEach(
    (Node element) {
      final nonceValue = (element as HtmlElement).nonce;
      if (_noncePattern.hasMatch(nonceValue)) {
        return nonceValue;
      }
    }.toJS,
  );
  return null;
}

/// Creates a script that will run properly when strict CSP is enforced.
///
/// More specifically, the script has the correct `nonce` value set.
HTMLScriptElement _createScript() {
  final nonce = _findNonce();

  return nonce == null ? HTMLScriptElement() : HTMLScriptElement()
    ..setAttribute('nonce', nonce!);
}

/// Runs `window.$dartRunMain()` by injecting a script tag.
///
/// We do this so that we don't see user exceptions bubble up in our own error
/// handling zone.
void runMain() {
  final scriptElement = _createScript()..htmlFor = r'window.$dartRunMain();';
  (document.body as HTMLBodyElement).append(scriptElement.toJSBox);
  // External tear-offs are not allowed.
  // ignore: unnecessary_lambdas
  Future.microtask(() => scriptElement.remove());
}
