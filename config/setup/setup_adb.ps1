$ErrorActionPreference = "Stop"

$ConfigDir = Split-Path $PSScriptRoot -Parent
$RepoRoot = Split-Path $ConfigDir -Parent
$AdbDir = Join-Path $ConfigDir "adb\platform-tools"
$AdbExecutable = Join-Path $AdbDir "adb.exe"
$AdbBin = $null

$SdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
if ($env:LOCALAPPDATA) {
    $SdkRoots += Join-Path $env:LOCALAPPDATA "Android\Sdk"
}
foreach ($SdkRoot in $SdkRoots) {
    if ([string]::IsNullOrWhiteSpace($SdkRoot)) {
        continue
    }

    $SdkAdb = Join-Path $SdkRoot "platform-tools\adb.exe"
    if (Test-Path $SdkAdb) {
        $AdbBin = Split-Path $SdkAdb -Parent
        break
    }
}

if (-not $AdbBin -and (Test-Path $AdbExecutable)) {
    $AdbBin = $AdbDir
}

if (-not $AdbBin) {
    $ExistingAdb = Get-Command adb -ErrorAction SilentlyContinue
    if ($ExistingAdb) {
        $AdbBin = Split-Path $ExistingAdb.Source -Parent
    }
}

if (-not $AdbBin) {
    $DownloadUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    $TemporaryDirectory = Join-Path $env:TEMP "mlrc-accs-adb-$([guid]::NewGuid().ToString('N'))"
    $ArchivePath = Join-Path $TemporaryDirectory "platform-tools.zip"
    try {
        New-Item -ItemType Directory -Path $TemporaryDirectory -ErrorAction Stop | Out-Null
        Write-Host "Downloading Android SDK Platform-Tools..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath -ErrorAction Stop
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $TemporaryDirectory -Force

        $ExtractedAdb = Join-Path $TemporaryDirectory "platform-tools\adb.exe"
        if (-not (Test-Path $ExtractedAdb)) {
            throw "The downloaded Platform-Tools archive did not contain adb.exe."
        }

        New-Item -ItemType Directory -Path $AdbDir -Force | Out-Null
        Copy-Item -Path (Join-Path (Split-Path $ExtractedAdb -Parent) "*") -Destination $AdbDir -Recurse -Force
        $AdbBin = $AdbDir
    } finally {
        Remove-Item -LiteralPath $TemporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$AdbExecutable = Join-Path $AdbBin "adb.exe"
if (-not (Test-Path $AdbExecutable)) {
    throw "ADB setup did not produce an executable at '$AdbExecutable'."
}
if (($env:Path -split ';') -notcontains $AdbBin) {
    $env:Path = "$AdbBin;$env:Path"
}

& $AdbExecutable version
if ($LASTEXITCODE -ne 0) {
    throw "ADB verification failed with exit code $LASTEXITCODE."
}
Write-Host "ADB is ready from $AdbBin." -ForegroundColor Green
