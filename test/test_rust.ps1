$ErrorActionPreference = "Stop"
$NumInstances = 4
$TempDir = Join-Path $env:TEMP "rust_test_suite"

Write-Host "=== 1. Setting up temporary test workspace in $TempDir ===" -ForegroundColor Cyan
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

$RustCode = @"
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
"@

$RsPath = Join-Path $TempDir "test_script.rs"
$ExePath = Join-Path $TempDir "test_script.exe"

Set-Content -Path $RsPath -Value $RustCode

Write-Host "=== 2. Compiling Rust test script with rustc ===" -ForegroundColor Cyan
rustc $RsPath -o $ExePath

Write-Host "=== 3. Launching $NumInstances parallel instances ===" -ForegroundColor Cyan
$Jobs = @()
for ($i = 1; $i -le $NumInstances; $i++) {
    $Jobs += Start-Job -ScriptBlock {
        param($exe, $id)
        & $exe $id
    } -ArgumentList $ExePath, $i
}

# Wait for all background jobs to finish and receive outputs
$Jobs | Wait-Job | Out-Null
foreach ($job in $Jobs) {
    Receive-Job -Job $job
    Remove-Job -Job $job
}

Write-Host "=== 4. Cleaning up temporary files ===" -ForegroundColor Cyan
Remove-Item -Path $TempDir -Recurse -Force

Write-Host "=== All $NumInstances Rust test instances passed successfully! ===" -ForegroundColor Green