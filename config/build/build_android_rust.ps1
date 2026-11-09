param(
    [Parameter(Mandatory = $true)]
    [string]$NdkDirectory
)

$ErrorActionPreference = "Stop"

$NdkDirectory = [System.IO.Path]::GetFullPath($NdkDirectory)
$NdkMetadata = Join-Path $NdkDirectory "source.properties"
if (-not (Test-Path -LiteralPath $NdkMetadata)) {
    throw "Android NDK metadata was not found at '$NdkMetadata'. Install the Flutter-required NDK version and retry."
}

$NdkBin = Join-Path $NdkDirectory "toolchains\llvm\prebuilt\windows-x86_64\bin"
if (-not (Test-Path -LiteralPath $NdkBin)) {
    throw "Windows Android NDK toolchain was not found at '$NdkBin'."
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "Cargo was not found on PATH. Install Rust and rerun this script."
}
if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    throw "Rustup was not found on PATH. Install Rust with rustup and rerun this script."
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ManifestPath = Join-Path $RepoRoot "rust_backend\Cargo.toml"
$JniLibsPath = Join-Path $RepoRoot "screen_mirror\android\app\src\main\jniLibs"
$Targets = @(
    @{
        Triple = "armv7-linux-androideabi"
        Abi = "armeabi-v7a"
        Linker = "armv7a-linux-androideabi23-clang.cmd"
    },
    @{
        Triple = "aarch64-linux-android"
        Abi = "arm64-v8a"
        Linker = "aarch64-linux-android23-clang.cmd"
    },
    @{
        Triple = "x86_64-linux-android"
        Abi = "x86_64"
        Linker = "x86_64-linux-android23-clang.cmd"
    }
)

$InstalledTargets = @(& rustup target list --installed)
if ($LASTEXITCODE -ne 0) {
    throw "Could not query installed Rust targets."
}
$MissingTargets = @($Targets | Where-Object { $_.Triple -notin $InstalledTargets })
if ($MissingTargets.Count -gt 0) {
    $TargetNames = @($MissingTargets | ForEach-Object { $_.Triple })
    Write-Host "Installing Rust Android targets: $($TargetNames -join ', ')" -ForegroundColor Cyan
    & rustup target add @TargetNames
    if ($LASTEXITCODE -ne 0) {
        throw "Installing Rust Android targets failed with exit code $LASTEXITCODE."
    }
}

foreach ($Target in $Targets) {
    $LinkerPath = Join-Path $NdkBin $Target.Linker
    if (-not (Test-Path -LiteralPath $LinkerPath)) {
        throw "NDK linker for '$($Target.Triple)' was not found at '$LinkerPath'."
    }

    $LinkerVariable = "CARGO_TARGET_$($Target.Triple.ToUpperInvariant().Replace('-', '_'))_LINKER"
    Set-Item -Path "Env:$LinkerVariable" -Value $LinkerPath

    Write-Host "Building Rust Android library for $($Target.Abi)..." -ForegroundColor Cyan
    & cargo build --release --manifest-path $ManifestPath --target $Target.Triple
    if ($LASTEXITCODE -ne 0) {
        throw "Rust build for '$($Target.Triple)' failed with exit code $LASTEXITCODE."
    }

    $BuiltLibrary = Join-Path $RepoRoot "rust_backend\target\$($Target.Triple)\release\libmlrc_accs_backend.so"
    if (-not (Test-Path -LiteralPath $BuiltLibrary)) {
        throw "Rust build completed but did not produce '$BuiltLibrary'."
    }

    $AbiDirectory = Join-Path $JniLibsPath $Target.Abi
    New-Item -ItemType Directory -Path $AbiDirectory -Force | Out-Null
    Copy-Item -LiteralPath $BuiltLibrary -Destination (Join-Path $AbiDirectory "libmlrc_accs_backend.so") -Force
}

Write-Host "Android Rust libraries built and packaged in '$JniLibsPath'." -ForegroundColor Green
