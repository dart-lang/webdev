import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'build script successfully generates client.js and version.dart',
    () async {
      final result = await Process.run('dart', ['run', 'tool/build.dart']);

      expect(
        result.exitCode,
        0,
        reason: 'Build script failed: ${result.stdout}\n${result.stderr}',
      );

      final clientJsFile = File(p.join('lib', 'src', 'injected', 'client.js'));
      expect(clientJsFile.existsSync(), isTrue);
      expect(clientJsFile.lengthSync(), greaterThan(0));

      final versionFile = File(p.join('lib', 'src', 'version.dart'));
      expect(versionFile.existsSync(), isTrue);
      expect(
        versionFile.readAsStringSync(),
        contains('const packageVersion ='),
      );
    },
  );
}
