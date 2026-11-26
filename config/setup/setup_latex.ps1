$ErrorActionPreference = "Stop"

Write-Host "=== Installing MiKTeX via winget ===" -ForegroundColor Cyan

$Winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $Winget) {
    throw "winget is not available. Install App Installer from Microsoft Store, then rerun this script."
}

& $Winget.Source install --exact --id MiKTeX.MiKTeX --source winget --scope user --silent --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) {
    throw "MiKTeX installation failed with exit code $LASTEXITCODE."
}

Write-Host "=== Refreshing environment variables ===" -ForegroundColor Cyan
$MachinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$UserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = (@($MachinePath, $UserPath, $env:Path) | Where-Object { $_ }) -join ";"

$Candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\x64\pdflatex.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\pdflatex.exe"),
    (Join-Path $env:LOCALAPPDATA "MiKTeX\miktex\bin\x64\pdflatex.exe"),
    (Join-Path $env:LOCALAPPDATA "MiKTeX\miktex\bin\pdflatex.exe"),
    (Join-Path ${env:ProgramFiles} "MiKTeX\miktex\bin\x64\pdflatex.exe"),
    (Join-Path ${env:ProgramFiles} "MiKTeX\miktex\bin\pdflatex.exe")
)
if (${env:ProgramFiles(x86)}) {
    $Candidates += Join-Path ${env:ProgramFiles(x86)} "MiKTeX\miktex\bin\x64\pdflatex.exe"
    $Candidates += Join-Path ${env:ProgramFiles(x86)} "MiKTeX\miktex\bin\pdflatex.exe"
}

$Pdflatex = Get-Command pdflatex -ErrorAction SilentlyContinue
if (-not $Pdflatex) {
    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate)) {
            $Pdflatex = Get-Item -LiteralPath $Candidate
            $env:Path = "$(Split-Path $Candidate -Parent);$env:Path"
            break
        }
    }
}

if (-not $Pdflatex) {
    throw "MiKTeX installed, but pdflatex.exe was not found. Restart the terminal and retry."
}

& $Pdflatex.Source --version
if ($LASTEXITCODE -ne 0) {
    throw "pdflatex verification failed with exit code $LASTEXITCODE."
}

Write-Host "=== Initializing MiKTeX packages ===" -ForegroundColor Cyan
$MiktexBin = Split-Path $Pdflatex.Source -Parent
$MiktexCli = Join-Path $MiktexBin "miktex.exe"
$MiktexUpdate = Join-Path $MiktexBin "miktex-update.exe"

if (Test-Path -LiteralPath $MiktexCli) {
    & $MiktexCli packages update
    if ($LASTEXITCODE -ne 0) {
        throw "MiKTeX package initialization failed with exit code $LASTEXITCODE."
    }

    $RequiredPackages = @(
        @{ Id = "ieeetran"; File = "IEEEtran.cls" },
        @{ Id = "amsmath"; File = "amsmath.sty" },
        @{ Id = "booktabs"; File = "booktabs.sty" },
        @{ Id = "graphics"; File = "graphicx.sty" },
        @{ Id = "url"; File = "url.sty" },
        @{ Id = "lmodern"; File = "lmodern.sty" },
        @{ Id = "lm"; File = "ot1lmr.fd" },
        @{ Id = "lastpage"; File = "lastpage.sty" },
        @{ Id = "psnfss"; File = "ot1ptm.fd" }
    )
    $Kpsewhich = Join-Path $MiktexBin "miktex-kpsewhich.exe"
    $MissingPackageIds = @()
    foreach ($RequiredPackage in $RequiredPackages) {
        $PackageFile = & $Kpsewhich $RequiredPackage.File 2>$null
        if (-not $PackageFile) {
            $MissingPackageIds += $RequiredPackage.Id
        }
    }

    if ($MissingPackageIds.Count -gt 0) {
        $PackageIdFile = Join-Path $env:TEMP "mlrc-miktex-packages.txt"
        Set-Content -LiteralPath $PackageIdFile -Value $MissingPackageIds -Encoding ASCII
        & $MiktexCli packages install --package-id-file=$PackageIdFile
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $PackageIdFile -Force -ErrorAction SilentlyContinue
            throw "MiKTeX IEEE document package installation failed with exit code $LASTEXITCODE."
        }
        Remove-Item -LiteralPath $PackageIdFile -Force -ErrorAction SilentlyContinue
    }
}
if (Test-Path -LiteralPath $MiktexUpdate) {
    & $MiktexUpdate --hide
    if ($LASTEXITCODE -ne 0) {
        throw "MiKTeX update failed with exit code $LASTEXITCODE."
    }
}

Write-Host "MiKTeX and pdflatex are ready." -ForegroundColor Green
