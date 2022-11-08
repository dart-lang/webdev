import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';

late Target serviceWorkerTarget;
late Browser browser;

final clickIconJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    chrome.action.onClicked.dispatch(tab);
  }
''';

final context = TestContext();

void main() async {
  group('Debug Extension Tests', () {
    setUpAll(() async {
      await context.setUp(
          enableMv3DebugExtension: true, serveDevTools: true, useSse: true);
      final browserUrl = context.browserUrl;
      browser = await puppeteer.connect(browserUrl: browserUrl);
      // browser = await puppeteer.launch(
      //   headless: false,
      //   args: [
      //     '--load-extension=debug_extension/prod_build',
      //     '--disable-extensions-except=${pathToExtension}',
      //     '--disable-features=DialMediaRouteProvider',
      //   ],
      // );

      browser.targets.forEach((target) => print(target.type));

      serviceWorkerTarget = await browser
          .waitForTarget((target) => target.type == 'service_worker');
    });

    test('Can use Dart Debug Extension', () async {
      final appTab = await browser.newPage();
      await appTab.goto('https://github.com/dart-lang/webdev',
          wait: Until.all([Until.domContentLoaded, Until.networkIdle]));
      await appTab.bringToFront();

      print('target types now.');

      browser.targets.forEach((target) => print(target.type));

      // print('getting sw target...');

      //   serviceWorkerTarget = await browser
      // .waitForTarget((target) => target.type == 'service_worker');
      // print('got target!');

      final worker = (await serviceWorkerTarget.worker)!;
      await worker.evaluate(clickIconJs);
      // Verify that the extension opened the Dart docs:
      // final newTabTarget = await browser
      //     .waitForTarget((target) => target.url == 'https://dart.dev/');
      browser.targets.forEach((target) => print(target.url));
      // final newTabPage = await newTabTarget.page;
      // expect(newTabPage, isNotNull);
    });
  });
}

  Future<String> _buildDebugExtension() async {
    final currentDir = Directory.current.path;
    if (!currentDir.endsWith('dwds')) {
      throw StateError(
          'Expected to be in /dwds directory, instead path was $currentDir.');
    }
    final extensionDir = '$currentDir/debug_extension_mv3';
    await Process.run(
      'tool/build_extension.sh',
      [],
      workingDirectory: extensionDir,
    );
    return '$extensionDir/compiled';
  }
