import 'dart:async';

import 'package:webdev/webdev.dart';
import 'package:build_runner/src/logging/std_io_logging.dart';
import 'package:logging/logging.dart';

Future main(List<String> args) async {
  // TODO(nshahan) See if build_runner wants to expose their listener.
  // Using log listener from build_runner to match output format.
  final logListener = Logger.root.onRecord.listen(stdIOLogListener);
  await webdevCommandRunner().run(args);
  await logListener?.cancel();
}
