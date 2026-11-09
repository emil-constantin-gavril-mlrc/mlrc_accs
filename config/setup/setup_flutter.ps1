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
    git -c core.longpaths=true clone -b stable https://github.com/flutter/flutter.git $FlutterDir
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter SDK clone failed. Git long-path support was enabled for this clone. If this left a partial checkout at '$FlutterDir', remove that directory and rerun setup."
    }
} else {
    Write-Host "=== 2. Flutter SDK already present. Checking for updates... ===" -ForegroundColor Cyan
    Push-Location $FlutterDir

    try {
        $WorkingTreeStatus = git -c core.longpaths=true status --porcelain
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect the Flutter SDK checkout."
        }
        if ($WorkingTreeStatus | Where-Object { $_ -match '^( D|D )' }) {
            throw "The Flutter SDK checkout is incomplete (tracked files are missing), likely due to a previous Windows path-length failure. Remove '$FlutterDir' and rerun setup to clone it again with Git long-path support enabled."
        }

        # Preserve local changes before updating.
        git -c core.longpaths=true stash --include-untracked
        if ($LASTEXITCODE -ne 0) {
            throw "Could not stash local Flutter SDK changes; refusing to overwrite the checkout."
        }
        git -c core.longpaths=true fetch origin
        if ($LASTEXITCODE -ne 0) {
            throw "Could not fetch Flutter updates."
        }
        git -c core.longpaths=true checkout stable
        if ($LASTEXITCODE -ne 0) {
            throw "Could not switch the Flutter SDK to the stable branch."
        }
        git -c core.longpaths=true pull origin stable
        if ($LASTEXITCODE -ne 0) {
            throw "Could not update the Flutter SDK stable branch."
        }
        git -c core.longpaths=true stash pop --index 2>$null
    } finally {
        Pop-Location
    }
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
if ($LASTEXITCODE -ne 0) {
    throw "Flutter doctor failed with exit code $LASTEXITCODE. Check network access to Flutter's artifact host and rerun setup."
}

Write-Host "=== Flutter setup on Windows completed successfully! Restart your terminal to refresh PATH. ===" -ForegroundColor Green