#!/bin/bash

# Copyright 2022 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# INSTRUCTIONS:

# Building DDC-compiled app (for development work):
# ./tool/build_extension.sh

# Building dart2js-compiled app (for release):
# ./tool/build_extension.sh prod

prod="false"

case "$1" in
    prod)
        prod="true"
        shift;;
esac

if [ $prod == true ]; then
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "Building dart2js-compiled extension to build/web_prod directory."
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    dart run build_runner build web -o build -r
    exit 1
fi

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Building DDC-compiled extension to build/web directory."
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
dart run build_runner build web -o build
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Updating the manifest.json file in build/web directory."
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
dart tool/update_dev_manifest.dart
