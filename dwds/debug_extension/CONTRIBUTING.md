Note: all is working, citc client is embed-dart-devtools-g3
Currently that is sending the wrong devtools uri

## Building

- With dart2js:

```
pub run build_runner build web -o build -r
```

- With DDC:

```
pub run build_runner build web -o build
```
## Local Development

### Update `manifest.json`:

* Change the `default_icon` in `manifest.json` to `dart_dev.png` (Note: this is not strictly necessary, but will help you to distinguish your local version of the extension from the published version)
* [For Googlers] The developer key is needed for local development and testing. Add one of the whitelisted keys to `web/manifest.json`. IMPORTANT: DO NOT COMMIT THE KEY.

```
{
    "name": "Dart Debug Extension",
    "key": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    ...
}
```

### Build and upload your local extension

* Build the extension following the instructions above (note only dart2js works: pub run build_runner build web -o build -r)
* Visit chrome://extensions
* Toggle "Developer mode" on
* Click the "Load unpacked" button
* Select the extension directory: `/dwds/debug_extension/web`

### Debug your local extension
* Click the Extensions puzzle piece, and pin the Dart Debug Extension with the dev icon (unpin the published version so you don't confuse them)
* You can now use the extension normally by clicking it when a local Dart web application has loaded in a Chrome tab
* To debug, visit chrome://extensions and click "Inspect view on background page" to open Chrome DevTools for the extension 
* More debugging information can be found in the [Chrome Developers documentation](https://developer.chrome.com/docs/extensions/mv3/devguide/)


## Deployment

- Update the version number in `web/manifest.json`.
- Zip `web/manifest.json`, `web/background.js`, and `dart.png`.
- Upload the `.zip` to the Chrome Web Store.
