#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
ADB_DIR="$CONFIG_DIR/adb/platform-tools"
ADB_BIN=""

SDK_ROOTS=(
    "${ANDROID_SDK_ROOT:-}"
    "${ANDROID_HOME:-}"
    "${HOME:+$HOME/Android/Sdk}"
)

for sdk_root in "${SDK_ROOTS[@]}"; do
    if [[ -n "$sdk_root" && -x "$sdk_root/platform-tools/adb" ]]; then
        ADB_BIN="$sdk_root/platform-tools"
        break
    fi
done

if [[ -z "$ADB_BIN" && -x "$ADB_DIR/adb" ]]; then
    ADB_BIN="$ADB_DIR"
fi

if [[ -z "$ADB_BIN" ]] && command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(dirname "$(command -v adb)")"
fi

if [[ -z "$ADB_BIN" ]]; then
    if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        echo "Installing ADB requires curl and Python 3 to download and extract Android SDK Platform-Tools." >&2
        exit 1
    fi

    DOWNLOAD_URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT

    echo "Downloading Android SDK Platform-Tools..."
    curl --fail --location --silent --show-error --retry 3 "$DOWNLOAD_URL" --output "$TEMP_DIR/platform-tools.zip"
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
        "$TEMP_DIR/platform-tools.zip" "$TEMP_DIR"

    if [[ ! -x "$TEMP_DIR/platform-tools/adb" ]]; then
        echo "The downloaded Platform-Tools archive did not contain adb." >&2
        exit 1
    fi

    mkdir -p "$ADB_DIR"
    cp -a "$TEMP_DIR/platform-tools/." "$ADB_DIR/"
    chmod +x "$ADB_DIR/adb"
    ADB_BIN="$ADB_DIR"
fi

ADB_EXECUTABLE="$ADB_BIN/adb"
if [[ ! -x "$ADB_EXECUTABLE" ]]; then
    echo "ADB setup did not produce an executable at '$ADB_EXECUTABLE'." >&2
    exit 1
fi

case ":$PATH:" in
    *":$ADB_BIN:"*) ;;
    *) export PATH="$ADB_BIN:$PATH" ;;
esac

"$ADB_EXECUTABLE" version
echo "ADB is ready from $ADB_BIN."
