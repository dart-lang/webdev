# DWDS webdev integration tests

This unpublished package runs DWDS integration tests from webdev. Currently it
runs the shared DWDS integration tests against apps that are built and served
by `build_runner` (through the build daemon).

`package:dwds` and `package:dwds_test_common` live in the Dart SDK
(`pkg/dwds` and `pkg/dwds_test_common`). This package depends on them through
git `dependency_overrides` pointing at the SDK's `main` branch, so these tests
always run against the latest DWDS.

## Layout

- `test/integration/fixtures/build_daemon_context.dart`: The
  `BuildDaemonTestContext`, the build daemon counterpart of the SDK's
  `FrontendServerTestContext`.
- `test/integration/build_daemon/`: Wrappers that run the shared integration
  test scenarios defined in `package:dwds_test_common/integration` with the
  `BuildDaemonTestContext`.
- `test/integration/`: Tests that don't need a build context.

## Running the tests

The tests require Chrome and a matching version of ChromeDriver. By default
they look for `google-chrome` and `chromedriver` on the `PATH`; set the
`CHROME_EXECUTABLE` and `CHROMEDRIVER_PATH` environment variables to use other
binaries.

```sh
dart pub upgrade
dart test
```

To test against local changes to DWDS, point the `dependency_overrides` at your
Dart SDK checkout in a `pubspec_overrides.yaml` file:

```yaml
dependency_overrides:
  dwds:
    path: <path to the sdk>/pkg/dwds
  dwds_test_common:
    path: <path to the sdk>/pkg/dwds_test_common
```
