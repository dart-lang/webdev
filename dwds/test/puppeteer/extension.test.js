// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const puppeteer = require('puppeteer');

let browser;
let appUrl;
let serviceWorker;

beforeAll(async () => {
  const [_, __, ___, extensionDirArg, appUrlArg] = process.argv;
  appUrl = appUrlArg;
  const pathToExtension = require('path').join(extensionDirArg);
  browser = await puppeteer.launch({
    headless: 'chrome',
    args: [
      `--disable-extensions-except=${pathToExtension}`,
      `--load-extension=${pathToExtension}`,
      '--disable-features=DialMediaRouteProvider',
    ],
  });
  const serviceWorkerTarget = await browser.waitForTarget(
    target => target.type() === 'service_worker'
  );
  serviceWorker = await serviceWorkerTarget.worker();
});

afterAll(async () => {
  await browser.close();
});

describe('Dart Debug Extension', () => {
  test('Clicking extension icon opens Dart docs', async () => {
    // Navigate to the app tab:
    const appTab = await browser.newPage();
    await appTab.goto(appUrl, { waitUntil: ['domcontentloaded', "networkidle2"] });
    await appTab.bringToFront();

    // Click on the Dart Debug Extension icon:
    await serviceWorker.evaluate(async () => {
      const activeTabs = await chrome.tabs.query({ active: true });
      const tab = activeTabs[0];
      chrome.action.onClicked.dispatch(tab);
    });

    // Verify that the extension opened the Dart docs:
    const newTabTarget = await browser.waitForTarget(
      target => target.url() === 'https://dart.dev/'
    );
    const newTabPage = await newTabTarget.page();
    expect(newTabPage).not.toBeNull();
  });
});