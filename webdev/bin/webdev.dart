import 'dart:async';

import 'package:webdev/src/webdev_command_runner.dart';

Future main(List<String> args) async {
  await webdevCommandRunner().run(args);
}
