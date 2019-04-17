## 2.0.0

## Breaking Changes

- The `serve` command will now only serve `web` by default.
- Deprecated the `--hot-reload` and `--live-reload` flags, in favor of the new
  `--auto=<action>` option which performs an action whenever a build completes.
  - The current supported actions are `restart` and `refresh`, which correspond
    to the old `--hot-reload` and `--live-reload` flags.
- Support building with `package:build_daemon` through `serve` command.
  - This should not affect most users but might break some workflows.

### Features

- Multiple webdev processes in the same package will now share builds and not
  conflict with each other.
- Added the `--debug` flag.
  - Runs a proxy dart vm service with limited functionality, which talks to the
    running in chrome.
  - Enables [devtools](https://github.com/flutter/devtools) for web apps.
    - For regular web apps currently this doesn't actually do anything yet,
      except for supported frameworks which will enable some tabs.
    - Use `alt+d` in the web app to launch devtools.
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

- Add default value for `--output` to be `build:web` for the `build` command
  and `NONE` for the `serve` command.
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
