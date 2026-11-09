#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./run_app.sh <debug|prod> [host|linux|android] [run|build]

Arguments:
  <debug|prod>             Select the debug or production configuration.
  [host|linux|android]     Target platform (default: host / Linux).
  [run|build]              Run the app or build an artifact (default: run).

Options:
  -h, --help               Show this help and exit.

Examples:
  ./run_app.sh debug                 Run on Linux desktop
  ./run_app.sh prod linux build      Build a production Linux app
  ./run_app.sh debug android        Run on a connected Android device/emulator
  ./run_app.sh prod android build   Build a production Android APK
EOF
}

for argument in "$@"; do
    if [[ "$argument" == "-h" || "$argument" == "--help" ]]; then
        usage
        exit 0
    fi
done

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    usage
    exit 1
fi

CONFIG_TYPE="$1"
TARGET="${2:-host}"
ACTION="${3:-run}"

if [[ "$CONFIG_TYPE" != "debug" && "$CONFIG_TYPE" != "prod" ]]; then
    usage
    exit 1
fi
if [[ "$TARGET" != "host" && "$TARGET" != "linux" && "$TARGET" != "android" ]]; then
    echo "Unsupported target on Linux. Choose host, linux, or android." >&2
    exit 1
fi
if [[ "$ACTION" != "run" && "$ACTION" != "build" ]]; then
    usage
    exit 1
fi
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "run_app.sh supports Linux hosts. Use run_app.ps1 on Windows." >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$PROJECT_ROOT/screen_mirror"
SETUP_DIR="$PROJECT_ROOT/config/setup"
CONFIG_FILE="config_debug.json"
if [[ "$CONFIG_TYPE" == "prod" ]]; then
    CONFIG_FILE="config_production.json"
fi
CONFIG_PATH="$PROJECT_ROOT/config/$CONFIG_FILE"

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Configuration file not found: $CONFIG_PATH" >&2
    exit 1
fi

LOCAL_FLUTTER="$PROJECT_ROOT/config/flutter/bin/flutter"
if [[ ! -x "$LOCAL_FLUTTER" ]] && ! command -v flutter >/dev/null 2>&1; then
    echo "Flutter was not found. Running the Flutter setup script..."
    bash "$SETUP_DIR/setup_flutter.sh"
fi

if [[ -x "$LOCAL_FLUTTER" ]]; then
    FLUTTER_COMMAND="$LOCAL_FLUTTER"
elif command -v flutter >/dev/null 2>&1; then
    FLUTTER_COMMAND="$(command -v flutter)"
else
    echo "Flutter setup completed, but Flutter could not be found." >&2
    exit 1
fi

if ! command -v rustc >/dev/null 2>&1 && [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
fi
if ! command -v rustc >/dev/null 2>&1; then
    echo "Rust was not found. Running the Rust setup script..."
    bash "$SETUP_DIR/setup_rust.sh"
    if [[ -f "$HOME/.cargo/env" ]]; then
        # shellcheck disable=SC1091
        . "$HOME/.cargo/env"
    fi
fi
if ! command -v rustc >/dev/null 2>&1; then
    echo "Rust setup completed, but rustc could not be found on PATH." >&2
    exit 1
fi

if [[ "$TARGET" == "host" ]]; then
    TARGET="linux"
fi

if [[ "$TARGET" == "linux" || "$TARGET" == "android" ]]; then
    echo "Ensuring Android SDK Platform-Tools (ADB) are available..."
    bash "$SETUP_DIR/setup_adb.sh"
    ADB_BIN="$PROJECT_ROOT/config/adb/platform-tools"
    if [[ ! -x "$ADB_BIN/adb" ]]; then
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
    fi
    if [[ -x "$ADB_BIN/adb" ]]; then
        export PATH="$ADB_BIN:$PATH"
    fi
    if ! command -v adb >/dev/null 2>&1; then
        echo "ADB setup completed, but adb could not be found on PATH." >&2
        exit 1
    fi
fi

if [[ "$TARGET" == "linux" ]]; then
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "Linux desktop dependencies could not be installed automatically. This setup supports apt-based distributions; install clang, cmake, ninja-build, pkg-config, libgtk-3-dev, liblzma-dev, and libstdc++ development headers, then retry." >&2
        exit 1
    fi
    MISSING_LINUX_DEPS=0
    for package in clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            MISSING_LINUX_DEPS=1
            break
        fi
    done
    if [[ "$MISSING_LINUX_DEPS" -eq 1 ]]; then
        echo "Installing Linux desktop build dependencies..."
        sudo apt-get update
        sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
    fi
fi

if [[ "$TARGET" == "android" ]]; then
    ANDROID_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
    if [[ ! -d "$ANDROID_SDK" ]]; then
        if command -v snap >/dev/null 2>&1; then
            if ! snap list android-studio >/dev/null 2>&1; then
                echo "Android SDK was not found. Installing Android Studio via snap..."
                sudo snap install android-studio --classic
            fi
        else
            echo "Android SDK is missing. Install Android Studio, complete its setup wizard, install the Android SDK and Platform-Tools, then rerun." >&2
            echo "Automatic Android Studio installation is available on Linux hosts with snap." >&2
            exit 1
        fi

        echo "Android Studio was installed. Open it once, complete the setup wizard, install the Android SDK and Platform-Tools, then rerun." >&2
        exit 1
    fi

    export ANDROID_HOME="$ANDROID_SDK"
    export ANDROID_SDK_ROOT="$ANDROID_SDK"
    if [[ -x "$LOCAL_FLUTTER" ]]; then
        FLUTTER_EXECUTABLE="$LOCAL_FLUTTER"
    else
        FLUTTER_EXECUTABLE="$(command -v "$FLUTTER_COMMAND")"
    fi
    FLUTTER_SDK="$(dirname "$(dirname "$FLUTTER_EXECUTABLE")")"
    FLUTTER_GRADLE_UTILS="$FLUTTER_SDK/packages/flutter_tools/lib/src/android/gradle_utils.dart"
    if [[ ! -f "$FLUTTER_GRADLE_UTILS" ]]; then
        echo "Could not determine Flutter's required Android NDK version because '$FLUTTER_GRADLE_UTILS' was not found." >&2
        exit 1
    fi
    NDK_VERSION="$(sed -nE "s/^[[:space:]]*const ndkVersion[[:space:]]*=[[:space:]]*'([^']+)'.*/\\1/p" "$FLUTTER_GRADLE_UTILS" | head -n 1)"
    if [[ -z "$NDK_VERSION" ]]; then
        echo "Could not read the required Android NDK version from '$FLUTTER_GRADLE_UTILS'." >&2
        exit 1
    fi

    echo "Accepting Android SDK licenses. Review and accept the prompts to continue."
    "$FLUTTER_COMMAND" doctor --android-licenses
    bash "$SETUP_DIR/setup_ndk.sh" "$ANDROID_SDK" "$NDK_VERSION"
    bash "$PROJECT_ROOT/config/build/build_android_rust.sh" "$ANDROID_SDK/ndk/$NDK_VERSION"

    if [[ "$ACTION" == "run" ]]; then
        ADB_DEVICES_OUTPUT="$(adb devices -l)" || {
            echo "Could not query Android devices with adb. Check the Android SDK Platform-Tools installation." >&2
            exit 1
        }
        ANDROID_DEVICE_IDS=()
        UNAUTHORIZED_DEVICE_IDS=()
        while read -r serial state _; do
            case "$state" in
                device) ANDROID_DEVICE_IDS+=("$serial") ;;
                unauthorized) UNAUTHORIZED_DEVICE_IDS+=("$serial") ;;
            esac
        done < <(printf '%s\n' "$ADB_DEVICES_OUTPUT" | tail -n +2)

        if [[ "${#ANDROID_DEVICE_IDS[@]}" -eq 0 ]]; then
            MESSAGE="No authorized Android device or running emulator was found. Flutter only listed desktop/web targets, so this launcher will not start one of those."
            if [[ "${#UNAUTHORIZED_DEVICE_IDS[@]}" -gt 0 ]]; then
                MESSAGE+=" Authorize device(s) ${UNAUTHORIZED_DEVICE_IDS[*]} by unlocking the phone and accepting its USB debugging prompt; then rerun."
            fi
            EMULATOR_EXECUTABLE="$ANDROID_SDK/emulator/emulator"
            if [[ -x "$EMULATOR_EXECUTABLE" ]]; then
                AVAILABLE_EMULATORS="$("$EMULATOR_EXECUTABLE" -list-avds)"
                if [[ -n "$AVAILABLE_EMULATORS" ]]; then
                    MESSAGE+=" Installed emulator(s): ${AVAILABLE_EMULATORS//$'\n'/, }. Start one in Android Studio Device Manager, then rerun."
                fi
            fi
            echo "$MESSAGE" >&2
            exit 1
        fi
        if [[ "${#ANDROID_DEVICE_IDS[@]}" -gt 1 ]]; then
            echo "Multiple authorized Android devices are connected: ${ANDROID_DEVICE_IDS[*]}. Leave one connected and rerun." >&2
            exit 1
        fi
        ANDROID_DEVICE_ID="${ANDROID_DEVICE_IDS[0]}"
    fi
fi

FLUTTER_ARGS=()
if [[ "$ACTION" == "run" ]]; then
    FLUTTER_ARGS+=(run)
    if [[ "$TARGET" == "android" ]]; then
        FLUTTER_ARGS+=(-d "$ANDROID_DEVICE_ID")
    else
        FLUTTER_ARGS+=(-d "$TARGET")
    fi
else
    FLUTTER_ARGS+=(build)
    if [[ "$TARGET" == "android" ]]; then
        FLUTTER_ARGS+=(apk)
    else
        FLUTTER_ARGS+=("$TARGET")
    fi
    if [[ "$CONFIG_TYPE" == "debug" ]]; then
        FLUTTER_ARGS+=(--debug)
    else
        FLUTTER_ARGS+=(--release)
    fi
fi
FLUTTER_ARGS+=("--dart-define-from-file=$CONFIG_PATH")

echo "=== $ACTION Flutter app ($CONFIG_TYPE, $TARGET) ==="
echo "Using config: $CONFIG_FILE"
cd "$PROJECT_DIR"
echo "=== Resolving Flutter packages ==="
"$FLUTTER_COMMAND" pub get
"$FLUTTER_COMMAND" "${FLUTTER_ARGS[@]}"
