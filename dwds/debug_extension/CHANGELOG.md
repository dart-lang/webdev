## 1.22

- Detect Dart applications and update the icon accordingly.

## 1.21

- Detect authentication issues and prompt accordingly.

## 1.20

- Return response when `dwds.startDebugging` is called.


## 1.19

- Support cross-extension communication for use with Google specific extensions.

## 1.18

- Depend on the latest `package:sse`.

## 1.17

- Depend on the latest `package:sse`.

## 1.16

- Depend on the latest `package:sse`.


## 1.15

- No longer send script parsed events when skipLists are supported,
  improving the IPL of Dart DevTools.

## 1.14

- Depend on the latest `package:sse`.


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
