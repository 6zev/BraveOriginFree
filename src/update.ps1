# BraveOriginFree - Update Checker / Installer
#
# Checks the official Brave GitHub releases for a newer Brave Origin build and,
# unless -CheckOnly is given, downloads and installs the portable win32-x64
# archive in place (with rollback to bin.bak on failure).

param([switch]$CheckOnly)

$ErrorActionPreference = "Stop"

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $AppDir
$BinDir = Join-Path $RootDir "bin"
$DataDir = Join-Path $RootDir "data"
$OriginExe = Join-Path $BinDir "brave.exe"
$VersionFile = Join-Path $RootDir "version.txt"

Write-Host "BraveOriginFree - Update Checker" -ForegroundColor Cyan
Write-Host ""

# --- Current version --------------------------------------------------------

$current = "unknown"
if (Test-Path $VersionFile) {
    $current = (Get-Content $VersionFile -Raw).Trim()
} elseif (Test-Path $OriginExe) {
    try { $current = (Get-Item $OriginExe).VersionInfo.FileVersion } catch {}
}
Write-Host "Installed: v$current" -ForegroundColor Gray

# --- Latest from GitHub -----------------------------------------------------

Write-Host "Checking for updates..." -ForegroundColor Yellow
try {
    $release = Invoke-WebRequest "https://api.github.com/repos/brave/brave-browser/releases/latest" -UseBasicParsing -TimeoutSec 20 |
        ConvertFrom-Json
    $latest = $release.tag_name -replace '^v', ''
    Write-Host "Latest:    v$latest" -ForegroundColor Gray
} catch {
    Write-Host "Could not reach GitHub. Check your internet." -ForegroundColor Red
    exit 1
}

# Compare as versions where possible, fall back to equality.
$isCurrent = $false
if ($current -eq $latest) {
    $isCurrent = $true
} else {
    try {
        $isCurrent = ([version]$current -ge [version]$latest)
    } catch { $isCurrent = $false }
}

if ($isCurrent) {
    Write-Host "You have the latest version." -ForegroundColor Green
    exit 0
}

if ($current -eq "unknown") {
    Write-Host "New version available: v$latest" -ForegroundColor Yellow
} else {
    Write-Host "Update available: v$current -> v$latest" -ForegroundColor Yellow
}

if ($CheckOnly) { exit 0 }

# --- Download ---------------------------------------------------------------

$zipName = "brave-origin-v$latest-win32-x64.zip"
$zipUrl  = "https://github.com/brave/brave-browser/releases/download/v$latest/$zipName"
$zipPath = Join-Path $RootDir $zipName

Write-Host "Downloading v$latest..." -ForegroundColor Yellow
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 900
} catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    exit 1
}

# --- Backup -----------------------------------------------------------------

$backup = Join-Path $RootDir "bin.bak"
if (Test-Path $backup) { Remove-Item -Recurse -Force $backup -ErrorAction SilentlyContinue }
if (Test-Path $BinDir) {
    try {
        Move-Item $BinDir $backup -Force
        Write-Host "Backed up old version to bin.bak" -ForegroundColor Gray
    } catch {
        Write-Host "Could not back up bin\: $_" -ForegroundColor Red
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# --- Extract ----------------------------------------------------------------

New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $BinDir -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Set-Content -Path $VersionFile -Value $latest -Encoding ASCII -NoNewline
    Write-Host "Updated to v$latest" -ForegroundColor Green
} catch {
    Write-Host "Extraction failed: $_" -ForegroundColor Red
    Remove-Item -Recurse -Force $BinDir -ErrorAction SilentlyContinue
    if (Test-Path $backup) { Move-Item $backup $BinDir -Force }
    exit 1
}

# Clean up the successful-update backup.
Remove-Item -Recurse -Force $backup -ErrorAction SilentlyContinue

# --- Re-apply activation ----------------------------------------------------
# Note: version upgrades do not reset Local State, but older installs may have
# lost it. Re-assert the two keys without touching anything else.

$LocalState = Join-Path $DataDir "Local State"
if (Test-Path $LocalState) {
    try {
        $state = Get-Content $LocalState -Raw | ConvertFrom-Json
        $changed = $false

        if ($null -eq $state.brave) { $state | Add-Member -MemberType NoteProperty -Name brave -Value ([pscustomobject]@{}) -Force }
        if ($null -eq $state.brave.origin) {
            $state.brave | Add-Member -MemberType NoteProperty -Name origin -Value ([pscustomobject]@{}) -Force
        }
        if ($state.brave.origin.purchase_validated -ne $true) {
            $state.brave.origin | Add-Member -MemberType NoteProperty -Name purchase_validated -Value $true -Force
            $changed = $true
        }

        if ($null -eq $state.skus) { $state | Add-Member -MemberType NoteProperty -Name skus -Value ([pscustomobject]@{}) -Force }
        if ($null -eq $state.skus.state) {
            $state.skus | Add-Member -MemberType NoteProperty -Name state -Value ([pscustomobject]@{}) -Force
        }
        if (-not $state.skus.state.PSObject.Properties.Name.Contains("67")) {
            $state.skus.state | Add-Member -MemberType NoteProperty -Name "67" -Value '{"credentials":{"items":{"6":"7"}}}' -Force
            $changed = $true
        }

        if ($changed) {
            $state | ConvertTo-Json -Depth 20 -Compress | Set-Content $LocalState -Encoding UTF8 -Force
            Write-Host "Activation re-applied" -ForegroundColor Green
        }
    } catch {
        Write-Host "Activation check skipped: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Run run.bat to start the updated browser." -ForegroundColor Cyan
