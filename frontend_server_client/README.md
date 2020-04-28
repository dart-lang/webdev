This package provides a client interface around the frontend_server compiler
which ships with the Dart SDK.

## Usage

TODO

## SDK Versioning Policy

This package keeps a relatively tight version constraint on the SDK to allow
for breaking changes in the frontend_server binary itself.

Specifically, releases of this package will have an upper bound of less than
the next _minor_ (middle) version number of the latest stable SDK. There are no
requirements for the lower bound (other than the package must pass tests on
that SDK).

The effect of this policy is that breaking changes will be allowed to the
frontend_server binary, but only in _minor_ SDK version releases.

**Note**: This also means that when a new stable SDK is released, this package
will also need a new version published on pub before users can get a valid
version solve.