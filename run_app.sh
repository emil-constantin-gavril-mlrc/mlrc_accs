#!/usr/bin/env bash
set -e

# Check if argument is provided and valid
if [ "$1" != "debug" ] && [ "$1" != "prod" ]; then
    echo "Usage: ./run_app.sh [debug|prod]"
    exit 1
fi

CONFIG_TYPE="$1"

# Get script directory and go one level up to project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Map argument to config file name
if [ "$CONFIG_TYPE" == "debug" ]; then
    CONFIG_FILE="config_debug.json"
else
    CONFIG_FILE="config_production.json"
fi

CONFIG_PATH="$PROJECT_ROOT/config/$CONFIG_FILE"

if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file not found at $CONFIG_PATH"
    exit 1
fi

echo "=== Launching Flutter App ($CONFIG_TYPE mode) ==="
echo "Using config: $CONFIG_FILE"

# Navigate to project root and run Flutter with the config file
cd "$PROJECT_ROOT"
flutter run -d linux --dart-define-from-file="$CONFIG_FILE"