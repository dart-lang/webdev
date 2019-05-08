import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'chrome_proxy_service.dart';

class Debugger {
  Debugger(this.mainProxy);

  ChromeProxyService mainProxy;

  WipDebugger get chromeDebugger => mainProxy.tabConnection.debugger;

  Future<Null> initialize() async {
    await chromeDebugger.enable();
  }

  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) async {
    throw UnimplementedError();
  }
}
