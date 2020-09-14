[![Pub Package](https://img.shields.io/pub/v/webdev.svg)](https://pub.dartlang.org/packages/webdev)
[![Build Status](https://travis-ci.org/dart-lang/webdev.svg?branch=master)](https://travis-ci.org/dart-lang/webdev)

A command-line tool for developing and deploying web applications with Dart.

## Requirements

The latest release of `webdev` requires Dart SDK `2.3` or later.
This corresponds to Flutter SDK `1.5` or later.

To use `webdev` with a package, make sure you have entries in `pubspec.yaml`
similar to:

```yaml
...
dev_dependencies:
  build_runner: ^1.6.2
  build_web_compilers: ^2.0.0
...
```

*`build_web_compilers` `^1.2.0` is supported, but with some limited
functionality.*

## Installation

`webdev` is not meant to be used as a dependency. Instead, it should be
["activated"][activating].

```console
$ pub global activate webdev
# or
$ flutter pub global activate webdev
```

Learn more about activating and using packages [here][pub global].

## Usage

`webdev` provides two commands: `serve` and `build`.

### `webdev serve`

```
Run a local web development server and a file system watcher that rebuilds on
changes.

Usage: webdev serve [arguments] [<directory>[:<port>]]...
    --auto                        Automatically performs an action after each
                                  build:

                                  restart: Reload modules and re-invoke main
                                  (loses current state)
                                  refresh: Performs a full page refresh.
                                  [restart, refresh]
    --[no-]debug                  Enable the launching of DevTools (Alt + D /
                                  Option + D). This also enables
                                  --launch-in-chrome.
    --[no-]debug-extension        Enable the backend for the Dart Debug
                                  Extension.
    --[no-]injected-client        Whether or not to inject the client.js script
                                  in web apps. This is required for all
                                  debugging related features, but may interact
                                  poorly with proxy servers or other
                                  environments.
                                  (defaults to on)

Advanced:
    --chrome-debug-port           Specify which port the Chrome debugger is
                                  listening on. If used with launch-in-chrome
                                  Chrome will be started with the debugger
                                  listening on this port.
    --hostname                    Specify the hostname to serve on.
                                  (defaults to "localhost")
    --[no-]launch-in-chrome       Automatically launches your application in
                                  Chrome with the debug port open. Use
                                  chrome-debug-port to specify a specific port
                                  to attach to an already running chrome
                                  instance instead.
    --log-requests                Enables logging for each request to the
                                  server.
    --tls-cert-chain              The file location to a TLS Certificate to
                                  create an HTTPs server.
                                  Must be used with tls-cert-key.
    --tls-cert-key                The file location to a TLS Key to create an
                                  HTTPs server.
                                  Must be used with tls-cert-chain.
    --start-paused                Starts the application paused after each time
                                  it is loaded.
                                  Must be used with either debug or
                                  debug-extension

Common:
-h, --help                        Print this usage information.
-o, --output                      A directory to write the result of a build to.
                                  Or a mapping from a top-level directory in the
                                  package to the directory to write a filtered
                                  build output to. For example "web:deploy".
                                  A value of "NONE" indicates that no "--output"
                                  value should be passed to `build_runner`.
                                  (defaults to "NONE")
-r, --[no-]release                Build with release mode defaults for builders.
    --[no-]build-web-compilers    If a dependency on `build_web_compilers` is
                                  required to run.
                                  (defaults to on)
-v, --verbose                     Enables verbose logging.

Run "webdev help" to see global options.
```

### `webdev build`

```
Run builders to build a package.

Usage: webdev build [arguments]
-h, --help                        Print this usage information.
-o, --output                      A directory to write the result of a build to.
                                  Or a mapping from a top-level directory in the
                                  package to the directory to write a filtered
                                  build output to. For example "web:deploy".
                                  A value of "NONE" indicates that no "--output"
                                  value should be passed to `build_runner`.
                                  (defaults to "web:build")
-r, --[no-]release                Build with release mode defaults for builders.
                                  (defaults to on)
    --[no-]build-web-compilers    If a dependency on `build_web_compilers` is
                                  required to run.
                                  (defaults to on)
-v, --verbose                     Enables verbose logging.

Run "webdev help" to see global options.
```

[activating]: https://www.dartlang.org/tools/pub/cmd/pub-global#activating-a-package
[pub global]: https://www.dartlang.org/tools/pub/cmd/pub-global
[Dart build system]: https://github.com/dart-lang/build
