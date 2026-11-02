# Build Daemon Integration Tests

The tests in this directory are wrappers around the shared integration test scenarios defined in `package:dwds_test_common/integration`.

They execute the test scenarios defined there using `build_runner` (via the build daemon) as the build client.
