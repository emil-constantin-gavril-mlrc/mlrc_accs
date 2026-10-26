$ErrorActionPreference = "Stop"

$InstallDir = Split-Path $PSScriptRoot -Parent
$FlutterDir = Join-Path $InstallDir "flutter"
$FlutterBin = Join-Path $FlutterDir "bin"

Write-Host "=== 1. Ensuring installation directory exists ===" -ForegroundColor Cyan
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

if (-not (Test-Path (Join-Path $FlutterDir ".git"))) {
    Write-Host "=== 2. Flutter SDK not found. Cloning repository via git ===" -ForegroundColor Cyan
    git clone https://github.com/flutter/flutter.git -b stable $FlutterDir
} else {
    Write-Host "=== 2. Flutter SDK already present. Checking for updates... ===" -ForegroundColor Cyan
    Push-Location $FlutterDir
    
    # Stash any untracked or local changes just in case, pull latest stable, then pop
    git stash --include-untracked
    git fetch origin
    git checkout stable
    git pull origin stable
    git stash pop --index 2>$null # Ignore stash errors if nothing was stashed
    
    Pop-Location
    Write-Host "Flutter repository updated successfully." -ForegroundColor Green
}

Write-Host "=== 3. Ensuring Flutter bin is in User PATH ===" -ForegroundColor Cyan
$CurrentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")

if ($CurrentPath -notlike "*$FlutterBin*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$FlutterBin", "User")
    $env:Path += ";$FlutterBin"
    Write-Host "Added $FlutterBin to User PATH." -ForegroundColor Green
} else {
    Write-Host "Flutter is already in User PATH." -ForegroundColor Yellow
}

Write-Host "=== 4. Running flutter doctor ===" -ForegroundColor Cyan
& "$FlutterBin\flutter.bat" doctor

Write-Host "=== Flutter setup on Windows completed successfully! Restart your terminal to refresh PATH. ===" -ForegroundColor Green