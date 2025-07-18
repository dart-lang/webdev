## 3.8.0-wip

## 3.7.2

- Fixed duplicate app logs on page refresh by preventing multiple stdout listeners for the same appId.
- Adds `--offline` flag [#2483](https://github.com/dart-lang/webdev/pull/2483).
- Support the `--hostname` flag when the `--tls-cert-key` and `--tls-cert-chain` flags are present [#2588](https://github.com/dart-lang/webdev/pull/2588).
- Update `dwds` constraint to `24.3.11`.

## 3.7.1

- Update `dwds` constraint to `24.3.5`.
- Added a utility method to locate `package_config.json` and set it in the `loadStrategy`.

## 3.7.0

- Update `dwds` constraint to `24.2.0`.
- Update `package:vm_service` to `>=14.0.0 <16.0.0`.
- Update `package:vm_service_interface` to `2.0.1`.

## 3.6.0

- Update `dwds` constraint to `24.1.0`.

- Support running from inside a pub workspace [#2498](https://github.com/dart-lang/webdev/pull/2498).

## 3.5.0

- Update `dwds` constraint to `24.0.0`.

## 3.4.0

- Update `dwds` constraint to `23.3.0`.

- Update `package:vm_service` constraint to `>=10.1.0 <15.0.0`. - [#2307](https://github.com/dart-lang/webdev/pull/2307)

## 3.3.0

- Update `dwds` constraint to `23.0.0`.

## 3.2.0

- Add dependency on `package:vm_service_interface`. - [#2262](https://github.com/dart-lang/webdev/pull/2262)
- Update `package:vm_service` constraint to `>=10.1.0 <14.0.0`. - [#2235](https://github.com/dart-lang/webdev/pull/2265)
- Update `dwds` constraint to `21.1.0`.

## 3.1.0

- Update the parameters passed to `Dwds.start`. - [#2231](https://github.com/dart-lang/webdev/pull/2231)
- Update `package:vm_service` constraint to `>=10.1.0 <13.0.0`. - [#2248](https://github.com/dart-lang/webdev/pull/2248)
- Update `dwds` constraint to `21.0.0`.

## 3.0.8

- Hide and deprecate now unsupported `--null-safety` option. - [#2206](https://github.com/dart-lang/webdev/pull/2206)
- Update Dart SDK constraint to `>=3.2.0-36.0.dev <4.0.0`. - [#2207](https://github.com/dart-lang/webdev/pull/2207)
- Update `dwds` constraint to `21.0.0`.

## 3.0.7

- Update `build_web_compilers` constraint to `^4.0.4`.
- Update SDK constraint to `>=3.1.0-340.0.dev <4.0.0`.
- Update `dwds` constraint to `20.0.1`.

## 3.0.6

- Update `dwds` constraint to `19.0.2`.
- Update SDK constraint to `>=3.1.0-254.0.dev <4.0.0`.

## 3.0.5

- Update `dwds` constraint to `19.0.1`.

## 3.0.4

- Update `dwds` constraint to `19.0.0`.

## 3.0.3

- Update `dwds` constraint to `18.0.2`.

## 3.0.2

- Update `build_daemon` constraint to `^4.0.0`.

## 3.0.1

- Update SDK constraint to `>=3.0.0-188.0.dev <4.0.0`.
  - Supports records.
- Use dwds `18.0.0`.

## 3.0.0

- Add `--enable-experiment` flag to webdev commands and pass it
  to the build runner and the expression compiler service.
- Update SDK constraint to `>=3.0.0-134.0.dev <4.0.0`.
- Update `package:vm_service` constraint to `>=10.1.0 <12.0.0`.
- Make all tests use sound null safety fixtures.

**Breaking changes**

- Support Dart 3.0-alpha breaking changes:
  - Do not pass `--(no)-sound-null-safety` flag to build daemon.
  - Update `build_web_compilers` constraint to `^4.0.0`.
  - Update `build_runner` constraint to `^2.4.0`.
  - Support changes in the SDK layout for Dart 3.0.

## 2.7.12

- Migrate Webdev to null-safety.

## 2.7.11

- Remove no longer used `ExpressionCompilerService.handler`.
- Update the min SDK constraint to 2.18.0.
- Update DWDS to `16.0.0`.

## 2.7.10

- Pin DWDS version to avoid dependency conflicts with `package:vm_service`.

## 2.7.9

- Add an option to pass user data directory to chrome: `user-data-dir`. Auto
  detect user data directory based on the current OS if `auto` is given as a
  value. If `null` is given as a value (default), fall back to the existing
  behavior (i.e. creating/reusing a temp directory).

  Note: not supported for Windows yet due to flakiness it introduces.

  Example using user-specified directory:

  ```
    webdev serve \
      --debug --debug-extension \
      --user-data-dir='/Users/<user>/Library/Application Support/Google/Chrome'
  ```

  Example using auto-detected directory:

  ```
    webdev serve \
      --debug --debug-extension \
      --user-data-dir=auto
  ```

- Update the min SDK constraint to 2.17.0.

## 2.7.8

- Update `vm_service` to `^8.1.0`.
- Enable expression evaluation by default.
- Update the Dart minimum SDK to `>=2.16.0`.
- Depend on the latest DWDS (12.0.0)

## 2.7.7

- Handle and log http request serving errors.
- Update SDK constraint to `>=2.15.0 <3.0.0`.

## 2.7.6

- Update SDK constraint to `>=2.14.0 <3.0.0`

## 2.7.5

- Depend on the latest `package:dwds`.
- Update min sdk constraint to `>=2.13.0`.
- Support the latest `package:build_daemon`.

## 2.7.4

- Allow the latest build_runner, build_web_compilers, and build_daemon packages.

## 2.7.3

- Depend on the latest `package:dwds`.
- Update min sdk constraint to `>=2.13.0-144.0.dev`.

## 2.7.2

- Depend on the latest `package:dwds`.
- Support new `null-safety` flag. See README.
- Support latest `package:vm_service` version `6.x.x`.
- Opt all dart files out of null safety for min SDK constraint update.

## 2.7.1

- Depend on the latest `package:sse`.
- Remove references to Flutter Web as webdev is no longer used with Flutter.
  Users should be using Flutter Tools shipped with the Flutter SDK.

## 2.7.0

- Add support for the Dart Development Service (DDS).
- Expand `package:vm_service` to version `>=3.0.0 <6.0.0`.
- Require at least `build_web_compilers` version `2.12.0`.
- Depend on the latest `package:dwds`.
- Fix issue where open http connections prevent the process for exiting.
- Add expression evaluation feature under `--enable-expression-evaluation` flag
  passed to `webdev` commands. The feature is disabled by default.
- Update min sdk constraint to `>=2.10.0`.

## 2.6.2

- Update min sdk constraint to `>=2.8.1`.

## 2.6.1

- Rollback release so that we no longer require a dev version of
  `package:build_web_compilers`.

## 2.6.0

- Require at least `build_web_compilers` version `2.12.0-dev.1`.
- Depend on the latest `package:dwds`.

## 2.5.9

- Depend on the latest `package:dwds`.

## 2.5.8

- Depend on the latest `package:dwds`.
- Fix an issue where all directories were built when using the `serve` command.

## 2.5.7

- Update min sdk constraint to `>=2.7.0`.

## 2.5.6

- Expand `package:vm_service` to version `>=3.0.0 <5.0.0`

## 2.5.5

- Bump the min sdk constraint to `2.6.0`.
- Require at least `build_web_compilers` version `2.6.1`.
  - Versions `<2.0.0` are not supported by any dart sdk `>=2.6.0`.
  - Versions `<2.6.1` have bugs that we want to avoid users running into.
- Depend on `package:vm_service` version `^2.0.0`.
- Depend on the latest `package:dwds`.

## 2.5.4

- Fix support for `--output=NONE` when building.
- Properly error if not in a Dart root while running the `daemon` command.
- Depend on the latest `package:sse`.
- Serve DevTools if either `--debug` or `--debug-extension` is provided.
- Publicize the option `--debug-extension`.

## 2.5.3

- Added a new `--launch-app` command line option.
  - Expects a package relative path to an html file, such as `web/app.html`.
  - Launches the specified application in chrome on startup instead of the
    server root.
  - Allows multiple apps, and will launch all of them.
  - Supported for the `daemon` and `serve` commands.
- Depend on the latest `package:dwds`.

## 2.5.2

- Update SDK dependency to minimum of 2.5.0.
- Support absolute file: URIs for libraries.
- Depend on the latest `package:dwds`.

## 2.5.1

- Depend on the latest `package:dwds`.

## 2.5.0

- TLS support has been added to the `serve` command through the addition of two
  new options `tls-cert-chain` and `tls-cert-key`.
- Added an explicit error if asked to build or serve anything other than a top
  level directory under a package. This never worked before but silently didn't
  actually do what the user expected.

## 2.4.1

- Depend on the latest `package:webkit_inspection_protocol`.

## 2.4.0

- Add a `--no-injected-client` option which can be used to work around issues
  relating to the injected `client.js` file. All debugging features must be
  disabled if you use this option.
- Depend on the latest `package:dwds`.

## 2.3.0

- Depend on the latest `package:dwds`.
- Depend on the latest `package:build_daemon`.

## 2.2.0

- Added a `fullReload` service extension which performs a full page refresh.
- Handle shutdown notifications from latest `build_daemon` protocol.

## 2.1.0

- Add an explicit error if there are no directories to serve. Typically this
  would happen if the user doesn't have a `web` directory.
- Add support for specifying `--hostname any`.
- DevTools no longer launches in a new window. This prevents an issue where
  pausing your application also pauses DevTools.
- Fix some edge cases for hot restart:
  - All restarts will now fire isolate create/destroy events, regardless of how
    they are triggered.
  - Fix a bug in the module invalidation/reload logic.

## 2.0.7

- Update minimum `package:build_runner` version to `1.5.0`.
- Use `HttpMultiServer` to fix bind issues with IPv6 / IPv4.

## 2.0.6

- Use latest `package:build_daemon`.

## 2.0.5

- Use `HttpMultiServer` to fix bind issues with IPv6 / IPv4.

## 2.0.4

- Fix loading apps in non-chrome browsers in --debug mode
  - Add a nice error if attempting to launch devtools in non-chrome browsers.
- Detect `flutter` and `flutter_test` dependencies and fail with a nice message.

## 2.0.3

- Support latest `package:build_daemon`.
- Fix Chrome issues while running through VS Code.

## 2.0.2

- Support `package:dwds` version `0.3.0`.

## 2.0.1

- Fix launching Chrome on Windows.

## 2.0.0

## Breaking Changes

- The `serve` command will now only serve `web` by default.
- Deprecated the `--hot-reload` and `--live-reload` flags, in favor of the new
  `--auto=<action>` option which performs an action whenever a build completes.
  - The current supported actions are `restart` and `refresh`, which correspond
    to the old `--hot-reload` and `--live-reload` flags.
- Support building with `package:build_daemon`. This allows shared builds as
  long as the build arguments are compatible.
  - This should not affect most users but might break some workflows.
  - Prompts are not supported, so you may have to pass the
    `-- --delete-conflicting-outputs` argument if you used to hit `y` at the
    prompt.

### Features

- Added the `--debug` flag.
  - Runs a proxy dart vm service with limited functionality, which talks to the
    running in chrome.
  - Enables [devtools](https://github.com/flutter/devtools) for web apps.
    - For regular web apps currently this doesn't actually do anything yet,
      except for supported frameworks which will enable some tabs.
    - Use `alt+d` (or `option+d` on Mac) in the web app to launch devtools.
- Allow build_web_compilers 2.x.

## 1.0.1

- Support `package:build_web_compilers` `v1.0.0`.

## 1.0.0

- Support `package:build_runner` `v1.0.0`.
- Add `--version` to CLI.

## 0.2.5

- Added support for the --hot-reload flag, if on build_runner >=0.10.2.

## 0.2.4+1

- Print `Creating build script` on startup so the user is aware of what the
  process is doing.

## 0.2.4

- Added support for the --live-reload flag, if on build_runner >=0.10.1.

## 0.2.3+2

- Support latest `package:build_runner`.

## 0.2.3+1

- Support Dart 2 stable.

## 0.2.3

- Update required Dart SDK and `package:build_runner` to support latest
  versions.

## 0.2.2

- Add default value for `--output` to be `build:web` for the `build` command and
  `NONE` for the `serve` command.
- Update to use lower-case constants from Dart `^2.0.0-dev.54`.

## 0.2.1

- Support `package:build_web_compilers` `v0.4.0`.
- Always pass the argument `--fail-on-severe` to the `build` command.
- Exit with an error if unsupported arguments are passed to `build` command.

## 0.2.0

- Pass the arguments supporting `directory:port` for the `serve` command.
- Add the requirement for `build_web_compilers` to `build` command.
- Renamed `--require-build-web-compilers` flag to `--build-web-compilers`.

## 0.1.4

- Require and use features from `build_runner` 0.8.2.
  - Added a `--[no]-release` flag.
- Require `build_web_compliers` 0.3.6 when running `serve`.
  - Unless the `--no-require-build-web-compilers` flag is provided.

## 0.1.3+1

- Support running `pub` when it's not in the environment path.

## 0.1.3

- Now runs on Windows.

## 0.1.2

- Remove check for `build_web_compilers`. Allows general support for
  `build_runner` from tools.
- Use `pub deps` to validate target directory.

## 0.1.1

- Checks for a dependency on `build_web_compilers`.
- Gracefully handle exceptions.

## 0.1.0

- Initial release. Supports basic invocation of `build` and `serve` with
  `build_runner: ^0.8.0`.
