import 'dart:io';

void main() {
  final uri = Uri.parse('file:///Users/markzipan/Projects/webdev/dwds_test_common/lib/fixtures/context.dart');
  print('Base: $uri');
  print('..: ${uri.resolve('..')}');
  print('../..: ${uri.resolve('../..')}');
  print('../../../: ${uri.resolve('../../../')}');
  print('../../../..: ${uri.resolve('../../../../')}');
}
