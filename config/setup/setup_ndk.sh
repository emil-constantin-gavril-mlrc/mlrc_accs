#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: setup_ndk.sh <android-sdk-path> <ndk-version>" >&2
    exit 2
fi

ANDROID_SDK="$1"
NDK_VERSION="$2"
NDK_DIRECTORY="$ANDROID_SDK/ndk/$NDK_VERSION"
NDK_METADATA="$NDK_DIRECTORY/source.properties"

if [[ -f "$NDK_METADATA" ]]; then
    echo "Android NDK $NDK_VERSION is already installed."
    exit 0
fi

ANDROID_CLI="$ANDROID_SDK/cmdline-tools/latest/bin/android"
if [[ -x "$ANDROID_CLI" ]]; then
    echo "Installing Android NDK $NDK_VERSION using Android CLI..."
    "$ANDROID_CLI" "--sdk=$ANDROID_SDK" sdk install "ndk/$NDK_VERSION"
else
    SDK_MANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
    if [[ ! -x "$SDK_MANAGER" ]]; then
        echo "Android package manager was not found. Expected Android CLI at '$ANDROID_CLI' or sdkmanager at '$SDK_MANAGER'." >&2
        exit 1
    fi

    echo "Installing Android NDK $NDK_VERSION using sdkmanager..."
    "$SDK_MANAGER" "--sdk_root=$ANDROID_SDK" --install "ndk;$NDK_VERSION"
fi

if [[ ! -f "$NDK_METADATA" ]]; then
    echo "Android package manager completed without installing NDK $NDK_VERSION at '$NDK_DIRECTORY'." >&2
    exit 1
fi

echo "Android NDK $NDK_VERSION is ready."
