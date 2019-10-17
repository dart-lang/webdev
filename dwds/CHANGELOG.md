## 0.7.5-dev

- The injected client's connection is now based off the request URI.
- Fix an issue where resuming while paused at the start would cause an error.
- Expose the `ChromeDebugException` class for error handling purposes.

## 0.7.4

- Deobfuscate DDC extension method stack traces.
- Properly get all libraries with the `legacy` module system.

## 0.7.3

- Correctly set `Isolate` state if debugging is initiated after the application
  has already started.

## 0.7.2

- Account for root directory path when using `package:` URIs with `DartUri`.

## 0.7.1

- Fix a bug where we would try to create a new isolate even for a failed
  hot restart. This created a race condition that would lead to a crash.
- Don't attempt to write a vm service request to a closed connection.
  - Instead we log a warning with the attempted request message and return.
- Make all `close` methods more robust by allowing them to be called more than
  once and returning the cached future from previous calls.
- Add explicit handling of app not loaded errors when handling chrome pause
  events.

## 0.7.0

- `DWDS.start` now requires an `AssetHandler` instead of `applicationPort`,
  `assetServerPort` and `applicationTarget`.
- Expose a `BuildRunnerAssetHandler` which proxies request to the asset server
  running within build runner.
- Support the Legacy Module strategy through the injected client.
- Support DDK sourcemap URIs.
- Update SDK dependency to minimum of 2.5.0.

### Bug Fixes:

- Fix handling of chrome pause events when we have no isolate loaded yet.

## 0.6.2

- Capture any errors that happen when handling SSE requests in the DevHandler
  and return an error response to the client code.
  - Log error responses in the client to the console.
- Handle empty Chrome exception descriptions.

## 0.6.1

- Add `isolateRef` to `Isolate`s `pauseEvent`s.
- Depend on the latest `package:vm_service`.
- Implements `invoke`.
- Adds support for VM object IDs for things that don't have Chrome object Ids
  (e.g. int, double, bool, null).

## 0.6.0

- Add new required parameter `enableDebugging` to `Dwds.start`. If `false` is
  provided, debug services will not run. However, reload logic will continue
  to work with the injected client.
- Handle injected client SSE errors.
- Handle a race condition when the browser is refreshed in the middle of setting
  up the debug services.

## 0.5.5

- Properly set the `pauseEvent` on the `Isolate`.
- Fix a race condition with Hot Restarts where the Isolate was not created in
  time for pause events.

## 0.5.4

- Fix issue where certain required fields of VM service protocol objects were
  null.
- Properly set the `exceptionPauseMode` on the `Isolate`.
- Depend on the latest `DevTools`.

## 0.5.3

- Fix issue where certain required fields of VM service protocol objects were
  null.

## 0.5.2

- Fix issue where certain required fields of VM service protocol objects were
  null.
- Properly display `Closure` names in the debug view.

## 0.5.1

- Fix an issue where missing source maps would cause a crash. A warning will
  now be logged to the console instead.
- Depend on the latest `package:webkit_inspection_protocol`.

## 0.5.0

- Fix an issue where we source map paths were not normalized.
- Added a check to tests for the variable DWDS_DEBUG_CHROME to run Chrome with a
  UI rather than headless.
- Catch unhandled errors in `client.js` and recommend using the
  `--no-injected-client` flag for webdev users.
- Add support for an SSE connection with Dart DevTools.
- Rename `wsUri` to `uri` on `DebugConnection` to reflect that the uri may not
  be a websocket.
- Depend on latest `package:vm_service`.

## 0.4.0

- Move `data` abstractions from `package:webdev` into `package:dwds`.
- Move debugging related handlers from `package:webdev` into `package:dwds`.
- Move injected client from `package:webdev` into `package:dwds`.
- Create new public entrypoint `dwds.dart`. Existing public API `services.dart`
  is now private.

## 0.3.3

- Add support for `getScript` for paused isolates.
- Add support for `onRequest` and `onResponse` listeners for the vm service.

## 0.3.2

- Add support for `scope` in `evaluate` calls.

## 0.3.1

- Improve error reporting for evals, give the full JS eval in the error message
  so it can be more easily reproduced.

## 0.3.0

- Change the exposed type on DebugService to VmServiceInterface

## 0.2.1

- Support `setExceptionPauseMode`.

## 0.2.0

- Added custom tokens to the `wsUri` for increased security.
  - Treating this as a breaking change because you now must use the `wsUri`
    getter to get a valid uri for connecting to the service, when previously
    combining the port and host was sufficient.

## 0.1.0

- Initial version
