## 1.13

- Add support for using WebSockets for connection debug backend.

## 1.12

- Update error message to potentially direct users to enable debugging.

## 1.11

- Fix issue where the extension would provide an invalid alert when attempting
  to launch for a non Dart application.

## 1.10

- Properly handle `sendCommand` errors.

## 1.9

- Look for Dart applications nested in iframes.

## 1.8

- Add support for batching scriptParsed events.

## 1.7

- Depend on latest `package:sse` to get retry logic.
