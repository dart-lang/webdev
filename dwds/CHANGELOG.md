## 0.5.0

- Fix an issue where we source map paths were not normalized.
- Added a check to tests for the variable DWDS_DEBUG_CHROME to run Chrome with a
  UI rather than headless.
- Add support for an SSE connection with Dart DevTools.
- Rename `wsUri` to `uri` on `DebugConnection` to reflect that the uri may not
  be a websocket.

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
