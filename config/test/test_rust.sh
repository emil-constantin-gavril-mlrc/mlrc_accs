#!/usr/bin/env bash
set -e

NUM_INSTANCES=4
TEMP_DIR="/tmp/rust_test_suite"

echo "=== 1. Setting up temporary test workspace in $TEMP_DIR ==="
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Write a simple Rust source file
cat << 'EOF' > "$TEMP_DIR/test_script.rs"
use std::env;
use std::thread;
use std::time::Duration;

fn main() {
    let args: Vec<String> = env::args().collect();
    let instance_id = args.get(1).unwrap_or(&"0".to_string()).clone();
    println!("[Instance {}] Rust verification test started...", instance_id);
    
    // Simulate some work
    thread::sleep(Duration::from_millis(200));
    
    println!("[SUCCESS] Instance {} completed verification!", instance_id);
}
EOF

echo "=== 2. Compiling Rust test script with rustc ==="
rustc "$TEMP_DIR/test_script.rs" -o "$TEMP_DIR/test_script"

echo "=== 3. Launching $NUM_INSTANCES parallel instances ==="
PIDS=()
for i in $(seq 1 $NUM_INSTANCES); do
    "$TEMP_DIR/test_script" "$i" &
    PIDS+=($!)
done

# Wait for all background instances to complete
for pid in "${PIDS[@]}"; do
    wait "$pid"
done

echo "=== 4. Cleaning up temporary files ==="
rm -rf "$TEMP_DIR"

echo "=== All $NUM_INSTANCES Rust test instances passed successfully! ==="