## Instructions on releasing Webdev

- From the `/tool` directory in the mono-repo root, run: `dart run release.dart -p webdev`
- Open a PR with those changes (example PR:
  https://github.com/dart-lang/webdev/pull/1498)
- Note: Before submitting your PR, test that everything is working by following
  instructions in the `webdev/example` [README](/example/README.md) to run the
  example app and connect to Dart DevTools.
- Once the PR is submitted, go to https://github.com/dart-lang/webdev/releases and create a new
  release, eg https://github.com/dart-lang/webdev/releases/tag/webdev-3.0.0. This should trigger
  the auto-publisher. Verify that the package is published.
- From the `/tool` directory in the mono-repo root, run: `dart run release.dart --reset -p webdev`
- Submit a PR with those changes.
