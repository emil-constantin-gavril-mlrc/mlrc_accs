param(
    [Parameter(Position = 0)]
    [string]$ConfigType,

    [Parameter(Position = 1)]
    [string]$Target = "host",

    [Parameter(Position = 2)]
    [string]$Action = "run",

    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    Write-Output @"
Usage: .\run_app.ps1 <debug|prod> [host|windows|android] [run|build]

Arguments:
  <debug|prod>              Select the debug or production configuration.
  [host|windows|android]     Target platform (default: host / Windows).
  [run|build]               Run the app or build an artifact (default: run).

Examples:
  .\run_app.ps1 debug                 Run on Windows desktop
  .\run_app.ps1 prod windows build    Build a production Windows app
  .\run_app.ps1 debug android         Run on a connected Android device/emulator
  .\run_app.ps1 prod android build    Build a production Android APK
"@
}

if ($Help) {
    Show-Usage
    return
}

if ($ConfigType -notin @("debug", "prod")) {
    Show-Usage
    throw "Configuration is required and must be 'debug' or 'prod'."
}
if ($Target -notin @("host", "windows", "linux", "android")) {
    Show-Usage
    throw "Unsupported target '$Target'."
}
if ($Action -notin @("run", "build")) {
    Show-Usage
    throw "Unsupported action '$Action'."
}

if ($env:OS -ne "Windows_NT") {
    throw "run_app.ps1 supports Windows hosts. Use run_app.sh on Linux."
}

$RepoRoot = $PSScriptRoot
$ProjectRoot = Join-Path $RepoRoot "screen_mirror"
$SetupDir = Join-Path $RepoRoot "config\setup"
$ConfigFile = if ($ConfigType -eq "debug") { "config_debug.json" } else { "config_production.json" }
$ConfigPath = Join-Path $RepoRoot "config\$ConfigFile"

if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

# Toolchain sandbox. Windows may run unsigned local SDK binaries (this repo's
# bundled dart.exe, and possibly cargo.exe) at Low integrity level, which
# silently denies every write under AppData and Temp - that kills flutter
# analyze/build at startup. Redirecting all toolchain write targets into this
# repo keeps builds independent of that Windows verdict.
$SandboxRoot = Join-Path $RepoRoot ".toolchain-sandbox"
foreach ($SandboxDir in @("APPDATA", "Temp", "pub-cache", "cargo-home\registry")) {
    New-Item -ItemType Directory -Path (Join-Path $SandboxRoot $SandboxDir) -Force | Out-Null
}
function Copy-CacheOnce {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $From)) { return }
    if (Get-ChildItem -LiteralPath $To -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return }
    Write-Host "Seeding build cache one time: $From -> $To" -ForegroundColor Yellow
    robocopy $From $To /E /XO /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Write-Warning "Cache seeding failed (robocopy exit $LASTEXITCODE); tools will download fresh instead."
    }
}
Copy-CacheOnce -From (Join-Path $env:LOCALAPPDATA "Pub\Cache") -To (Join-Path $SandboxRoot "pub-cache")
Copy-CacheOnce -From (Join-Path $env:USERPROFILE ".cargo\registry") -To (Join-Path $SandboxRoot "cargo-home\registry")
$env:APPDATA = Join-Path $SandboxRoot "APPDATA"
$env:TEMP = Join-Path $SandboxRoot "Temp"
$env:TMP = $env:TEMP
$env:PUB_CACHE = Join-Path $SandboxRoot "pub-cache"
$env:CARGO_HOME = Join-Path $SandboxRoot "cargo-home"
$env:DART_METRICS_ENABLED = "false"
$LogDirectory = Join-Path $RepoRoot "logs"
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

if ($Target -eq "host") {
    $Target = "windows"
}
if ($Target -eq "linux") {
    throw "A Windows host cannot build or run the Linux desktop target. Use an Android target or run this project on Linux."
}

if ($Target -eq "windows") {
    $LinkProbeDirectory = Join-Path $ProjectRoot ".symlink-check-$([guid]::NewGuid().ToString('N'))"
    $LinkProbeTarget = Join-Path $LinkProbeDirectory "target"
    $LinkProbePath = Join-Path $LinkProbeDirectory "link"
    try {
        New-Item -ItemType Directory -Path $LinkProbeDirectory -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath $LinkProbeTarget -Value "symlink check" -ErrorAction Stop
        New-Item -ItemType SymbolicLink -Path $LinkProbePath -Target $LinkProbeTarget -ErrorAction Stop | Out-Null
    } catch {
        throw "Windows symbolic-link creation is unavailable. Enable Developer Mode in Settings (run 'start ms-settings:developers') or run PowerShell as an administrator, then rerun this command. Details: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $LinkProbePath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $LinkProbeTarget -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $LinkProbeDirectory -Force -ErrorAction SilentlyContinue
    }
}

$LocalFlutter = Join-Path $RepoRoot "config\flutter\bin\flutter.bat"
if (-not (Test-Path $LocalFlutter) -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "Flutter was not found. Running the Flutter setup script..." -ForegroundColor Yellow
    & (Join-Path $SetupDir "setup_flutter.ps1")
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Flutter setup failed with exit code $LASTEXITCODE."
    }
}

if (Test-Path $LocalFlutter) {
    $FlutterCommand = $LocalFlutter
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
    $FlutterCommand = "flutter"
} else {
    throw "Flutter setup completed, but Flutter could not be found."
}

$RustBin = Join-Path $HOME ".cargo\bin"
if (-not (Get-Command rustc -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $RustBin "rustc.exe"))) {
    Write-Host "Rust was not found. Running the Rust setup script..." -ForegroundColor Yellow
    & (Join-Path $SetupDir "setup_rust.ps1")
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Rust setup failed with exit code $LASTEXITCODE."
    }
}
if (Test-Path $RustBin) {
    $env:Path = "$RustBin;$env:Path"
}
if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) {
    throw "Rust setup completed, but rustc could not be found on PATH."
}

if ($Target -in @("windows", "android")) {
    Write-Host "Ensuring Android SDK Platform-Tools (ADB) are available..." -ForegroundColor Yellow
    & (Join-Path $SetupDir "setup_adb.ps1")
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw "ADB setup completed, but adb could not be found on PATH."
    }
}

if ($Target -eq "android") {
    $AndroidSdk = $env:ANDROID_SDK_ROOT
    if (-not $AndroidSdk -or -not (Test-Path $AndroidSdk)) { $AndroidSdk = $env:ANDROID_HOME }
    if (-not $AndroidSdk -or -not (Test-Path $AndroidSdk)) { $AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }

    if (-not (Test-Path $AndroidSdk)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "Android Studio was not found. Installing it with winget..." -ForegroundColor Yellow
            winget install --id Google.AndroidStudio --exact --silent --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) {
                throw "Android Studio installation failed with exit code $LASTEXITCODE."
            }
        } else {
            throw "Android SDK is missing and winget is unavailable. Install Android Studio, complete its setup wizard, install the Android SDK and Platform-Tools, then rerun this command."
        }

        throw "Android Studio was installed. Open it once, complete the setup wizard, install the Android SDK and Platform-Tools, then rerun this command."
    }

    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $FlutterSdk = Join-Path $RepoRoot "config\flutter"
    if (-not (Test-Path (Join-Path $FlutterSdk "packages\flutter_tools\lib\src\android\gradle_utils.dart"))) {
        $FlutterExecutable = (Get-Command $FlutterCommand -ErrorAction Stop).Source
        $FlutterSdk = Split-Path (Split-Path $FlutterExecutable -Parent) -Parent
    }
    $FlutterGradleUtils = Join-Path $FlutterSdk "packages\flutter_tools\lib\src\android\gradle_utils.dart"
    if (-not (Test-Path $FlutterGradleUtils)) {
        throw "Could not determine Flutter's required Android NDK version because '$FlutterGradleUtils' was not found."
    }
    $NdkVersionMatch = [regex]::Match((Get-Content -LiteralPath $FlutterGradleUtils -Raw), "const ndkVersion\s*=\s*'([^']+)'")
    if (-not $NdkVersionMatch.Success) {
        throw "Could not read the required Android NDK version from '$FlutterGradleUtils'."
    }
    $NdkVersion = $NdkVersionMatch.Groups[1].Value

    Write-Host "Accepting Android SDK licenses. Review and accept the prompts to continue." -ForegroundColor Yellow
    & $FlutterCommand doctor --android-licenses
    if ($LASTEXITCODE -ne 0) {
        throw "Android license setup failed. Rerun and accept the Android SDK licenses."
    }

    & (Join-Path $SetupDir "setup_ndk.ps1") -AndroidSdk $AndroidSdk -NdkVersion $NdkVersion
    & (Join-Path $RepoRoot "config\build\build_android_rust.ps1") `
        -NdkDirectory (Join-Path $AndroidSdk "ndk\$NdkVersion")
    if ($LASTEXITCODE -ne 0) {
        throw "Rust Android library build failed with exit code $LASTEXITCODE."
    }

    if ($Action -eq "run") {
        $AdbDevicesOutput = & adb devices -l
        if ($LASTEXITCODE -ne 0) {
            throw "Could not query Android devices with adb. Check the Android SDK Platform-Tools installation."
        }

        $AndroidDevices = @()
        $UnauthorizedDevices = @()
        foreach ($DeviceLine in $AdbDevicesOutput) {
            if ($DeviceLine -match '^\s*(\S+)\s+(\S+)(?:\s|$)') {
                if ($Matches[2] -eq "device") {
                    $AndroidDevices += $Matches[1]
                } elseif ($Matches[2] -eq "unauthorized") {
                    $UnauthorizedDevices += $Matches[1]
                }
            }
        }

        if ($AndroidDevices.Count -eq 0) {
            $EmulatorExecutable = Join-Path $AndroidSdk "emulator\emulator.exe"
            $AvailableEmulators = @()
            if (Test-Path $EmulatorExecutable) {
                $AvailableEmulators = @(& $EmulatorExecutable -list-avds)
            }

            $Message = "No authorized Android device or running emulator was found. Flutter only listed desktop/web targets, so this launcher will not start one of those."
            if ($UnauthorizedDevices.Count -gt 0) {
                $Message += " Authorize device(s) $($UnauthorizedDevices -join ', ') by unlocking the phone and accepting its USB debugging prompt; then rerun."
            }
            if ($AvailableEmulators.Count -gt 0) {
                $Message += " Installed emulator(s): $($AvailableEmulators -join ', '). Start one in Android Studio Device Manager, then rerun."
            }
            throw $Message
        }
        if ($AndroidDevices.Count -gt 1) {
            throw "Multiple authorized Android devices are connected: $($AndroidDevices -join ', '). Leave one connected and rerun."
        }
        $AndroidDeviceId = $AndroidDevices[0]
    }
}

if ($Target -eq "windows") {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $VsInstall = $null
    $VsInstallWithComponents = $null
    $VsComponents = @(
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "Microsoft.VisualStudio.Component.VC.ATL"
    )
    if (Test-Path $VsWhere) {
        $VsInstall = & $VsWhere -latest -products * -property installationPath
        $VsInstallWithComponents = & $VsWhere -latest -products * -requires $VsComponents -property installationPath
    }
    if (-not $VsInstallWithComponents) {
        $VsSetupExitCode = 0
        if ($VsInstall) {
            $VsInstaller = Join-Path (Split-Path $VsWhere -Parent) "setup.exe"
            if (-not (Test-Path $VsInstaller)) {
                throw "Visual Studio is installed at '$VsInstall', but its installer was not found at '$VsInstaller'. Repair Visual Studio Installer, then rerun."
            }

            Write-Host "Visual Studio is installed but its C++ workload or ATL component is missing. Adding the required components..." -ForegroundColor Yellow
            $VsArguments = "modify --installPath `"$VsInstall`" --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.ATL --includeRecommended --passive --norestart"
            $VsSetupProcess = Start-Process -FilePath $VsInstaller -ArgumentList $VsArguments -Verb RunAs -Wait -PassThru
            $VsSetupExitCode = $VsSetupProcess.ExitCode
        } else {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                throw "Windows desktop builds require Visual Studio 2022 with the Desktop development with C++ workload and C++ ATL. Install them manually, then rerun this command."
            }

            Write-Host "Visual Studio C++ build tools were not found. Installing the required workload with winget..." -ForegroundColor Yellow
            winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --override "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.ATL --includeRecommended" --accept-package-agreements --accept-source-agreements
            $VsSetupExitCode = $LASTEXITCODE
        }

        if (Test-Path $VsWhere) {
            $VsInstallWithComponents = & $VsWhere -latest -products * -requires $VsComponents -property installationPath
        }
        if (-not $VsInstallWithComponents) {
            throw "Visual Studio C++ workload and ATL setup failed with exit code $VsSetupExitCode. Open Visual Studio Installer, add Desktop development with C++ and C++ ATL, then rerun."
        }
        if ($VsSetupExitCode -ne 0) {
            Write-Warning "Visual Studio setup returned exit code $VsSetupExitCode, but the required C++ workload and ATL component are installed."
        }
    }
}

$FlutterArgs = @()
if ($Action -eq "run") {
    $FlutterArgs += "run"
    if ($Target -eq "android") {
        $FlutterArgs += @("-d", $AndroidDeviceId)
    } else {
        $FlutterArgs += @("-d", $Target)
    }
} else {
    $FlutterArgs += "build"
    if ($Target -eq "android") {
        $FlutterArgs += "apk"
    } else {
        $FlutterArgs += $Target
    }
    $FlutterArgs += if ($ConfigType -eq "debug") { "--debug" } else { "--release" }
}
$FlutterArgs += @("--dart-define-from-file=$ConfigPath")
$FlutterArgs += @("--dart-define=MLRC_LOG_DIR=$LogDirectory")

Write-Host "=== $Action Flutter app ($ConfigType, $Target) ===" -ForegroundColor Cyan
Write-Host "Using config: $ConfigPath" -ForegroundColor Yellow

Push-Location $ProjectRoot
try {
    Write-Host "=== Resolving Flutter packages ===" -ForegroundColor Cyan
    & $FlutterCommand pub get
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter dependency resolution failed with exit code $LASTEXITCODE. Check network access and repair the Pub cache with 'flutter pub cache repair', then retry."
    }

    & $FlutterCommand @FlutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter $Action failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
