# Ensure script execution policies allow running local scripts if needed
# Set-ExecutionPolicy Unrestricted -Scope Process

Write-Host "=== 1. Installing Rust via winget ===" -ForegroundColor Cyan
winget install --id Rustlang.Rustup -e --silent --accept-package-agreements --accept-source-agreements

Write-Host "=== 2. Refreshing Environment Variables ===" -ForegroundColor Cyan
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "=== 3. Verifying Installation ===" -ForegroundColor Green
rustc --version
cargo --version

Write-Host "=== Important: MSVC Build Tools ===" -ForegroundColor Yellow
Write-Host "Make sure you have Visual Studio C++ Build Tools installed on Windows for native linking."
Write-Host "If missing, run: winget install Microsoft.VisualStudio.2022.BuildTools --override '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'" -ForegroundColor Yellow

Write-Host "=== Rust setup on Windows completed! Restart your terminal to refresh PATH globally. ===" -ForegroundColor Cyan