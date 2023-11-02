## Building

- For development: `dart run tool/build_extension.dart`
- For release: ` dart run tool/build_extension.dart --prod`

The dart2js-compiled extension will be located in the `/compiled` directory.

## Local Development

### \[For Googlers\] Create an `extension_key.txt` file:

- Create a `extension_key.txt` file at the root of `/debug_extension`. Paste in
  the value of one of the whitelisted developer keys into this txt file.
  IMPORTANT: DO NOT COMMIT THE KEY. It will be copied into the `manifest.json`
  when you build the extension.

### Build and upload your local extension

- Build the extension following the instructions above
- Visit chrome://extensions
- Toggle "Developer mode" on
- Click the "Load unpacked" button
- Select the extension directory: `/compiled`

### Debug your local extension

- Click the Extensions puzzle piece, and pin the Dart Debug Extension with the
  dev icon (unpin the published version so you don't confuse them)
- You can now use the extension normally by clicking it when a local Dart web
  application has loaded in a Chrome tab
- To debug, visit chrome://extensions and click "Inspect view on background
  page" to open Chrome DevTools for the extension
- More debugging information can be found in the
  [Chrome Developers documentation](https://developer.chrome.com/docs/extensions/mv3/devguide/)

## Release process

- Update the version in `web/manifest_mv2.json`, `web/manifest_mv3.json`, `pubspec.yaml`, and in the
  `CHANGELOG`.
- Follow the instructions above to build the release version of the extension.

> \*At this point, you should manually verify that everything is working by
> following the steps in [Local Development](#local-development), except load
> the extension from the `compiled` directory. You will need to add an extension
> key to the `manifest.json` file in `compiled` to test locally.

- Open a PR to submit the version change.
- Once submitted, pull the changes down to your local branch, and create a zip
  of the `compiled` directory. **Remove the Googler extension key that was added
  by the builder to the `manifest.json` file.**
- Rename the zip `version_XX.XX.XX.zip` (eg, `version_1.24.0.zip`) and add it to
  the go/dart-debug-extension-zips folder

> _You must be a Googler to do this. Ask for help if not._

- Go to the
  [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole).
- At the top-right, under Publisher, select dart-bat.

> _If you don’t see dart-bat as an option, you will need someone on the Dart
> team to add you to the dart-bat Google group._

- Under Items, select the "Dart Debug Extension".
- Go to “Package” then select “Upload new package”.

> _The first time you do this, you will be asked to pay a $5 registration fee.
> The registration fee can be expensed._

- Upload the zip file you created in step 4.
- Save as draft, and verify that the new version is correct.
- Publish. The extension will be published immediately after going through the
  review process.

## Rollback process

> The Chrome Web Store Developer Dashboard does not support rollbacks. Instead
> you must re-publish an earlier version. This means that the extension will
> still have to go through the review process, which can take anywhere from a
> few hours (most common) to a few days.

- Find the previous version you want to rollback to in the
  go/dart-debug-extension-zips folder.

> _You must be a Googler to do this. Ask for help if not._

- Unzip the version you have chosen, and in `manifest.json` edit the version
  number to be the next sequential version after the current "bad" version (eg,
  the bad version is `1.28.0` and you are rolling back to version `1.27.0`.
  Therefore you change `1.27.0` to `1.29.0`).
- Re-zip the directory and rename it to the new version number. Add it to the
  go/dart-debug-extension-zips folder.
- Now, follow steps 6 - 11 in [Release process](#release-process).
