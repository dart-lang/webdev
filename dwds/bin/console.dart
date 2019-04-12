/// A trivial console for driving DWDS.

import 'package:dwds/src/chrome_proxy_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

const debugPort = 9222;

ChromeConnection connection;
ChromeTab tab;
ChromeProxyService proxy;
WipConnection tabConnection;

main() async {

  await setUp();
  await doStuff();
  // print("ok, now we're done");

}

setUp() async {
     connection = ChromeConnection('localhost', debugPort);
     tab = await connection.getTab((t) => true);
     proxy = await ChromeProxyService.create(connection, (x) async => x, '.*');
     print(proxy.tabConnection);
          print(proxy.tabConnection.page);
     tabConnection = await tab.connect();
    await tabConnection.runtime.enable();
    await tabConnection.debugger.enable();
}

sp(ScriptParsedEvent e) {
    print("console parsing ${e.script}");

}

doStuff() async {
  
  tabConnection.debugger.onScriptParsed.listen(sp);
  print("done?");
  // return Future.delayed(Duration(seconds: 10));

}