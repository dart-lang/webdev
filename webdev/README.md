[![Build Status](https://travis-ci.org/dart-lang/webdev.svg?branch=master)](https://travis-ci.org/dart-lang/webdev)

A CLI for Dart web development.

__*Note: Under heavy development.*__

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
-r, --[no-]release                Build with release mode defaults for builders.
-o, --output                      A directory to write the result of a build to. Or a mapping from a top-level directory in the package to the directory to write a filtered build output to. For example "web:deploy".
                                  A value of "NONE" indicates that no "--output" value should be passed to `build_runner`.
                                  (defaults to "NONE")

-v, --verbose                     Enables verbose logging.
    --[no-]build-web-compilers    If a dependency on `build_web_compilers` is required to run.
                                  (defaults to on)

    --hostname                    Specify the hostname to serve on
                                  (defaults to "localhost")

    --log-requests                Enables logging for each request to the server.
    --live-reload                 Automatically refreshes the page after each build.

Run "webdev help" to see global options.
```

### `webdev build`

```console
$ webdev help build
Run builders to build a package.

Usage: webdev build [arguments]
-h, --help                        Print this usage information.
-r, --[no-]release                Build with release mode defaults for builders.
                                  (defaults to on)

-o, --output                      A directory to write the result of a build to. Or a mapping from a top-level directory in the package to the directory to write a filtered build output to. For example "web:deploy".
                                  A value of "NONE" indicates that no "--output" value should be passed to `build_runner`.
                                  (defaults to "web:build")

-v, --verbose                     Enables verbose logging.
    --[no-]build-web-compilers    If a dependency on `build_web_compilers` is required to run.
                                  (defaults to on)

Run "webdev help" to see global options.
```
