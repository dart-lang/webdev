#!/bin/bash

# Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

echo "Running pub upgrade on all packages"

pushd dwds
dart pub upgrade
popd

pushd example
dart pub upgrade
popd

pushd frontend_server_client
dart pub upgrade
popd

pushd frontend_server_common
dart pub upgrade
popd

pushd webdev
dart pub upgrade
popd

# test input packages
pushd fixtures

pushd _webdevSmoke
dart pub upgrade
popd

pushd _webdevSoundSmoke
dart pub upgrade
popd

pushd _test
dart pub upgrade
popd

pushd _testSound
dart pub upgrade
popd

pushd _testPackage
dart pub upgrade
popd

pushd _testPackageSound
dart pub upgrade
popd

pushd _testCircular1
dart pub upgrade
popd

pushd _testCircular2
dart  pub upgrade
popd

pushd _testCircular1Sound
dart pub upgrade
popd

pushd _testCircular2Sound
dart pub upgrade
popd

popd
echo "Done running pub upgrade"
