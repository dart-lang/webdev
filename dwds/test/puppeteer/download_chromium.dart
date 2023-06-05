import 'package:puppeteer/puppeteer.dart';

void main() async {
  final chromePath = await downloadChrome();
  print('DOWNLOADED CHROME: ${chromePath.executablePath}');
}