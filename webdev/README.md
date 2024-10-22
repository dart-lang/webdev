A command-line tool for developing and deploying web applications with Dart.

## Requirements

The latest release of `webdev` requires Dart SDK `2.18.0` or later.

To use `webdev` with a package, add it to the `dev_dependencies` in `pubspec.yaml`:

```console
$ dart pub add dev:webdev
```

## Usage

`webdev` provides two commands: `serve` and `build`.

Run them with `dart run webdev serve` and `dart run webdev build`.

### `webdev serve`

```
Run a local web development server and a file system watcher that rebuilds on
changes.

Usage: webdev serve [arguments] [<directory>[:<port>]]...
    --auto                                 Automatically performs an action
                                           after each build:

                                           restart: Reload modules and re-invoke
                                           main (loses current state)
                                           refresh: Performs a full page
                                           refresh.
                                           [restart, refresh]
    --[no-]debug                           Enable the launching of DevTools (Alt
                                           + D / Option + D). This also enables
                                           --launch-in-chrome.
    --[no-]debug-extension                 Enable the backend for the Dart Debug
                                           Extension.
    --[no-]injected-client                 Whether or not to inject the
                                           client.js script in web apps. This is
                                           required for all debugging related
                                           features, but may interact poorly
                                           with proxy servers or other
                                           environments.
                                           (defaults to on)

Advanced:
    --chrome-debug-port                    Specify which port the Chrome
                                           debugger is listening on. If used
                                           with launch-in-chrome Chrome will be
                                           started with the debugger listening
                                           on this port.
    --hostname                             Specify the hostname to serve on.
                                           (defaults to "localhost")
    --[no-]launch-in-chrome                Automatically launches your
                                           application in Chrome with the debug
                                           port open. Use chrome-debug-port to
                                           specify a specific port to attach to
                                           an already running chrome instance
                                           instead.
    --user-data-dir                        Use with launch-in-chrome to specify
                                           user data directory to pass to
                                           chrome. Will start chrome window
                                           logged into default profile with
                                           enabled extensions. Use `auto` as a
                                           value to infer the default directory
                                           for the current OS. Note: only
                                           supported for Mac OS X and linux
                                           platforms.
    --log-requests                         Enables logging for each request to
                                           the server.
    --tls-cert-chain                       The file location to a TLS
                                           Certificate to create an HTTPs
                                           server.
                                           Must be used with tls-cert-key.
    --tls-cert-key                         The file location to a TLS Key to
                                           create an HTTPs server.
                                           Must be used with tls-cert-chain.

Common:
-h, --help                                 Print this usage information.
-o, --output                               A directory to write the result of a
                                           build to. Or a mapping from a
                                           top-level directory in the package to
                                           the directory to write a filtered
                                           build output to. For example
                                           "web:deploy".
                                           A value of "NONE" indicates that no
                                           "--output" value should be passed to
                                           `build_runner`.
                                           (defaults to "NONE")
-r, --[no-]release                         Build with release mode defaults for
                                           builders.
    --[no-]build-web-compilers             If a dependency on
                                           `build_web_compilers` is required to
                                           run.
                                           (defaults to on)
-e, --[no-]enable-expression-evaluation    Enable expression evaluation features
                                           in the debugger.
                                           (defaults to on)
-v, --verbose                              Enables verbose logging.

Run "webdev help" to see global options.

```

### `webdev build`

```
Run builders to build a package.

Usage: webdev build [arguments]
-h, --help                                 Print this usage information.
-o, --output                               A directory to write the result of a
                                           build to. Or a mapping from a
                                           top-level directory in the package to
                                           the directory to write a filtered
                                           build output to. For example
                                           "web:deploy".
                                           A value of "NONE" indicates that no
                                           "--output" value should be passed to
                                           `build_runner`.
                                           (defaults to "web:build")
-r, --[no-]release                         Build with release mode defaults for
                                           builders.
                                           (defaults to on)
    --[no-]build-web-compilers             If a dependency on
                                           `build_web_compilers` is required to
                                           run.
                                           (defaults to on)
-e, --[no-]enable-expression-evaluation    Enable expression evaluation features
                                           in the debugger.
                                           (defaults to on)
-v, --verbose                              Enables verbose logging.

Run "webdev help" to see global options.
```
