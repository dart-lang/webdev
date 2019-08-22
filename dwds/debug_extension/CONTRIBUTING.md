## Building

- With dart2js:

```
pub run build_runner build web -o build -r
```

- With DDC:

```
pub run build_runner build web -o build
```

## Deployment

- Update the version number in `web/manifest.json`.
- Zip `web/manifest.json`, `web/background.js`, and `dart.png`.
- Upload the `.zip` to the Chrome Web Store.