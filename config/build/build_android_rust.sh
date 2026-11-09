#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: build_android_rust.sh <android-ndk-directory>" >&2
    exit 2
fi

NDK_DIRECTORY="$(cd "$1" && pwd)"
if [[ ! -f "$NDK_DIRECTORY/source.properties" ]]; then
    echo "Android NDK metadata was not found under '$NDK_DIRECTORY'." >&2
    exit 1
fi

NDK_BIN="$NDK_DIRECTORY/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [[ ! -d "$NDK_BIN" ]]; then
    echo "Linux Android NDK toolchain was not found at '$NDK_BIN'." >&2
    exit 1
fi
for tool in cargo rustup; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool was not found on PATH. Install Rust with rustup and retry." >&2
        exit 1
    fi
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_PATH="$PROJECT_ROOT/rust_backend/Cargo.toml"
JNI_LIBS_PATH="$PROJECT_ROOT/screen_mirror/android/app/src/main/jniLibs"
TARGETS=(
    "armv7-linux-androideabi|armeabi-v7a|armv7a-linux-androideabi23-clang"
    "aarch64-linux-android|arm64-v8a|aarch64-linux-android23-clang"
    "x86_64-linux-android|x86_64|x86_64-linux-android23-clang"
)

INSTALLED_TARGETS="$(rustup target list --installed)"
for target_spec in "${TARGETS[@]}"; do
    IFS='|' read -r target abi linker <<< "$target_spec"
    if ! grep -Fxq "$target" <<< "$INSTALLED_TARGETS"; then
        echo "Installing Rust Android target: $target"
        rustup target add "$target"
    fi
done

for target_spec in "${TARGETS[@]}"; do
    IFS='|' read -r target abi linker <<< "$target_spec"
    linker_path="$NDK_BIN/$linker"
    if [[ ! -x "$linker_path" ]]; then
        echo "NDK linker for '$target' was not found or is not executable: '$linker_path'." >&2
        exit 1
    fi

    target_env="${target^^}"
    target_env="${target_env//-/_}"
    export "CARGO_TARGET_${target_env}_LINKER=$linker_path"

    echo "Building Rust Android library for $abi..."
    cargo build --release --manifest-path "$MANIFEST_PATH" --target "$target"

    built_library="$PROJECT_ROOT/rust_backend/target/$target/release/libmlrc_accs_backend.so"
    if [[ ! -s "$built_library" ]]; then
        echo "Rust build completed but did not produce '$built_library'." >&2
        exit 1
    fi

    abi_directory="$JNI_LIBS_PATH/$abi"
    mkdir -p "$abi_directory"
    cp "$built_library" "$abi_directory/libmlrc_accs_backend.so"
done

echo "Android Rust libraries built and packaged in '$JNI_LIBS_PATH'."
