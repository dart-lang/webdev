#!/bin/bash


if [[ $TRAVIS_OS_NAME == "windows" ]]; then
    echo Installing Google Chrome Stable...
    chromedriver.exe --version
    # Install Chrome via Chocolatey while `addons: chrome` doesn't seem to work on Windows yet
    # https://travis-ci.community/t/installing-google-chrome-stable-but-i-cant-find-it-anywhere/2118
    choco install googlechrome --acceptlicense --yes --no-progress --ignore-checksums

    PROGRAMFILES_X86="$(cmd //c 'echo %ProgramFILES(x86)%')"
    CHROME_PATH="Google\Chrome\Application\chrome.exe"
    if [ -f "$PROGRAMFILES\\$CHROME_PATH" ]; then
        echo "Found chrome at $PROGRAMFILES\\$CHROME_PATH"
        export CHROMEDRIVER_BINARY="$PROGRAMFILES\\$CHROME_PATH"
    elif [ -f "$PROGRAMFILES_X86\\$CHROME_PATH" ]; then
        echo "Found chrome at $PROGRAMFILES_X86\\$CHROME_PATH"
        export CHROMEDRIVER_BINARY="$PROGRAMFILES_X86\\$CHROME_PATH"
    elif [ -f "$LOCALAPPDATA\\$CHROME_PATH" ]; then
        echo "Found chrome at $LOCALAPPDATA\\$CHROME_PATH"
        export CHROMEDRIVER_BINARY="$LOCALAPPDATA\\$CHROME_PATH"
    else
        echo "Unable to find chrome!"
        exit 1
    fi
    export CHROMEDRIVER_OS=win32

    choco install chromedriver --acceptlicense --yes --no-progress --ignore-checksums
    chromedriver.exe --version
else
    export CHROMEDRIVER_BINARY=/usr/bin/google-chrome
    export CHROMEDRIVER_OS=linux64
    export CHROME_LATEST_VERSION=$("$CHROMEDRIVER_BINARY" --version | cut -d' ' -f3 | cut -d'.' -f1)
    export CHROME_DRIVER_VERSION=$(wget -qO- https://chromedriver.storage.googleapis.com/LATEST_RELEASE_$CHROME_LATEST_VERSION)
    wget https://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_$CHROMEDRIVER_OS.zip
    unzip "chromedriver_${CHROMEDRIVER_OS}.zip"
fi

export CHROMEDRIVER_ARGS=--no-sandbox

if [[ $TRAVIS_OS_NAME == "windows" ]]; then
    export PATH=$PATH:$APPDATA/Roaming/Pub/Cache/bin
    echo "After path"
    chromedriver.exe --version
else
    export PATH=$PATH:~/.pub-cache/bin
fi
