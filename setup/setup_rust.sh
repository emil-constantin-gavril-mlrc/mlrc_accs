#!/usr/bin/env bash
set -e

echo "=== 1. Updating package manager and installing build dependencies ==="
sudo apt-get update
sudo apt-get install -y build-essential curl pkg-config libssl-dev libasound2-dev libudev-dev libusb-1.0-0-dev

echo "=== 2. Installing Rust via rustup ==="
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

echo "=== 3. Sourcing Cargo environment ==="
source "$HOME/.cargo/env"

echo "=== 4. Verifying Installation ==="
rustc --version
cargo --version

echo "=== Rust setup on Linux completed successfully! ==="