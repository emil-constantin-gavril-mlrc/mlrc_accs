param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("debug", "prod")]
    [string]$ConfigType
)

$ErrorActionPreference = "Stop"

# Get the directory where this script resides, then go one level up to project root
$RepoRoot = $PSScriptRoot
$ProjectRoot = [System.IO.Path]::Combine($RepoRoot, "screen_mirror")

# Map config type to file name
$ConfigFile = if ($ConfigType -eq "debug") { "config_debug.json" } else { "config_production.json" }
$ConfigPath = [System.IO.Path]::Combine($RepoRoot, "config", $ConfigFile)

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found at: $ConfigPath"
    exit 1
}

Write-Host "=== Launching Flutter App ($ConfigType mode) ===" -ForegroundColor Cyan
Write-Host "Using config: $ConfigPath" -ForegroundColor Yellow

# Navigate to project root and run Flutter with the config file
Push-Location $ProjectRoot
flutter run -d windows --dart-define-from-file=$ConfigPath
Pop-Location