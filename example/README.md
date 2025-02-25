# Running the example app

1. Run `dart run build_runner build` from `webdev/` directory to update build
   artifacts.
1. From `example/`, run `dart run webdev serve --debug --verbose` (Note: all
   options can be found by running `dart run webdev help serve`)
1. Type opt/alt-d in the browser. This is required to start the VM.
1. \[OPTIONAL\] If you need to connect a locally running DevTools (instructions
   for running
   [here](https://github.com/flutter/devtools/blob/master/CONTRIBUTING.md)),
   then close the DevTools that automatically opened in the previous step. Copy
   and paste the debug URI (should be logged in your terminal) into the DevTools
   connection box.

### Note:

If you get this error:

`The /webdev/webdev/pubspec.yaml file has changed since the /webdev/webdev/pubspec.lock file was generated, please run "dart pub get" again.`

You need to do the following:

- `rm webdev/webdev/pubspec.lock`
- Then, from `/webdev/webdev` run `dart pub get`
