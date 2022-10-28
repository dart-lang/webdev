# Running the example app

1. In the root directory of `webdev`, run
   `pub global activate --source path webdev`
1. Uncomment the dwds dependency override in `/webdev/webdev/pubspec.yaml`, then
   run `dart run build_runner build` from `/webdev/webdev` directory
   - *Note: You will have to comment and build, and then uncomment and build,
     each time you need to pick up new changes*
1. From `/webdev/example`, run `webdev serve --debug --verbose` (Note: all
   options can be found by running `webdev help serve`)
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
