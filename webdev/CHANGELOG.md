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
