param(
    [Parameter(Mandatory = $true)]
    [string]$AndroidSdk,

    [Parameter(Mandatory = $true)]
    [string]$NdkVersion
)

$ErrorActionPreference = "Stop"

$NdkDirectory = Join-Path $AndroidSdk "ndk\$NdkVersion"
$NdkMetadata = Join-Path $NdkDirectory "source.properties"
if (Test-Path $NdkMetadata) {
    Write-Host "Android NDK $NdkVersion is already installed." -ForegroundColor Green
    return
}

$AndroidCli = Join-Path $AndroidSdk "cmdline-tools\latest\bin\android.exe"
if (Test-Path $AndroidCli) {
    Write-Host "Installing Android NDK $NdkVersion using Android CLI..." -ForegroundColor Cyan
    & $AndroidCli "--sdk=$AndroidSdk" sdk install "ndk/$NdkVersion"
} else {
    $SdkManager = Join-Path $AndroidSdk "cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not (Test-Path $SdkManager)) {
        throw "Android SDK package manager was not found. Expected Android CLI at '$AndroidCli' or sdkmanager at '$SdkManager'."
    }

    Write-Host "Installing Android NDK $NdkVersion using sdkmanager..." -ForegroundColor Cyan
    & $SdkManager "--sdk_root=$AndroidSdk" --install "ndk;$NdkVersion"
}

if ($LASTEXITCODE -ne 0) {
    throw "Android NDK $NdkVersion installation failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path $NdkMetadata)) {
    throw "Android package manager completed without installing NDK $NdkVersion at '$NdkDirectory'."
}

Write-Host "Android NDK $NdkVersion is ready." -ForegroundColor Green
