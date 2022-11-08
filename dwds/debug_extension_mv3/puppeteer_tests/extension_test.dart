import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

late Target serviceWorkerTarget;
late Browser browser;

final clickIconJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    chrome.action.onClicked.dispatch(tab);
  }
''';

void main() async {
  group('Debug Extension Tests', () {
    setUpAll(() async {
      final pathToExtension =
          '/Users/elliottbrooks/dev/webdev/dwds/debug_extension_mv3/compiled';

      print('launching...');
      browser = await puppeteer.launch(
        headless: true,
        args: [
          '--disable-extensions-except=${pathToExtension}',
          '--load-extension=${pathToExtension}',
          '--disable-features=DialMediaRouteProvider',
        ],
      );

      print('getting sw...');

      serviceWorkerTarget = await browser
          .waitForTarget((target) => target.type == 'service_worker');
    });

    test('Can use Dart Debug Extension', () async {
      final appTab = await browser.newPage();
      await appTab.goto('https://github.com/dart-lang/webdev',
          wait: Until.all([Until.domContentLoaded, Until.networkIdle]));
      await appTab.bringToFront();

      final worker = (await serviceWorkerTarget.worker)!;
      await worker.evaluate(clickIconJs);
      // Verify that the extension opened the Dart docs:
      final newTabTarget = await browser
          .waitForTarget((target) => target.url == 'https://dart.dev/');
      final newTabPage = await newTabTarget.page;
      expect(newTabPage, isNotNull);
    });
  });
}
