Dart Web Developer Service

__*Note: Under heavy development.*__

The Dart Web Developer Service (DWDS) allows developer tools designed
to work with the native Dart VM to also work with Dart Web
applications compiled with
[DDC](https://webdev.dartlang.org/tools/dartdevc), built/served with
[webdev](https://webdev.dartlang.org/tools/webdev), and run in Chrome.

DWDS will be integrated into the webdev.

At a basic level, DWDS proxies between:
* Developer tools that are written against the [Dart VM Service Protocol](https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md)
* Execution environments that expose the
[Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol)
