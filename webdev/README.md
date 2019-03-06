[![Build Status](https://travis-ci.org/dart-lang/webdev.svg?branch=master)](https://travis-ci.org/dart-lang/webdev)

A CLI for Dart web development.

See the [Dart 2 Web Migration Guide](https://webdev.dartlang.org/dart-2) for
more information.

## Installation

```console
$ pub global activate webdev
```

## Usage

`webdev` provides two commands: `serve` and `build`.

### `webdev serve`

```console
$ webdev help serve
Run a local web development server and a file system watcher that re-builds on changes.

Usage: webdev serve [arguments] [<directory>[:<port>]]...
-h, --help                        Print this usage information.
-o, --output                      A directory to write the result of a build to. Or a mapping from a top-level directory in the package to the directory to write a filtered build output to. For example "web:deploy".
                                  A value of "NONE" indicates that no "--output" value should be passed to `build_runner`.
                                  (defaults to "NONE")

-r, --[no-]release                Build with release mode defaults for builders.
    --[no-]build-web-compilers    If a dependency on `build_web_compilers` is required to run.
                                  (defaults to on)

-v, --verbose                     Enables verbose logging.
    --chrome-debug-port           Specify which port the Chrome debugger is listenting on. If used with launch-in-chrome Chrome will be started with the debugger listening on this port.
    --[no-]debugger               Enable the launching of DevTools (Alt + D). Must use with either --launch-in-chrome or --chrome-debug-port.
    --hostname                    Specify the hostname to serve on.
                                  (defaults to "localhost")

    --hot-restart                 Automatically reloads changed modules after each build and restarts your application.
                                  Can't be used with live-reload.

    --launch-in-chrome            Automatically launches your application in Chrome with the debug port open. Use chrome-debug-port to specify a specific port.
    --live-reload                 Automatically refreshes the page after each successful build.
                                  Can't be used with hot-restart.

    --log-requests                Enables logging for each request to the server.

Run "webdev help" to see global options.
```

### `webdev build`

```console
$ webdev help build
Run builders to build a package.

Usage: webdev build [arguments]
-h, --help                        Print this usage information.
-o, --output                      A directory to write the result of a build to. Or a mapping from a top-level directory in the package to the directory to write a filtered build output to. For example "web:deploy".
                                  A value of "NONE" indicates that no "--output" value should be passed to `build_runner`.
                                  (defaults to "web:build")

-r, --[no-]release                Build with release mode defaults for builders.
                                  (defaults to on)

    --[no-]build-web-compilers    If a dependency on `build_web_compilers` is required to run.
                                  (defaults to on)

-v, --verbose                     Enables verbose logging.

Run "webdev help" to see global options.
```
