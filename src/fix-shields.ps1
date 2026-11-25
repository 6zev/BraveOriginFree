# BraveOriginFree - Brave Shields Filter List Diagnostics & Repair
#
# Background: the default Shields filter lists ("EasyList", "Brave Default
# Adblock Filters", ...) are NOT bundled inside the portable zip. Brave fetches
# them through the component updater ("Ad Block Updater" / "Brave Ad Block List
# Catalog", served from adblock-data.s3.brave.com) and caches them inside the
# profile under an `adblock` component directory.
#
# Because of that, the usual causes of "all default filter lists disappeared"
# are:
#   1. --disable-component-update on the command line  -> updater never runs
#   2. a brand-new/removed --user-data-dir             -> cache is empty
#   3. deleting the data\ folder between launches
#   4. Brave running while the repair/update is applied
#
# This script diagnoses the profile, checks the launcher flags, and can force
# the updater to re-seed by clearing and re-fetching the adblock component.

param(
    [switch]$Status,
    [switch]$Force,
    [switch]$FixFlags,
    [string]$DataDir,
    [string]$BinDir
)

$ErrorActionPreference = "Stop"

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $AppDir
if ([string]::IsNullOrEmpty($DataDir)) { $DataDir = Join-Path $RootDir "data" }
if ([string]::IsNullOrEmpty($BinDir)) { $BinDir = Join-Path $RootDir "bin" }

function Write-Info($m) { Write-Host "  $m" -ForegroundColor Gray }
function Write-Ok($m)   { Write-Host "[O] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "[x] $m" -ForegroundColor Red }

Write-Host ""
Write-Host " ============================================" -ForegroundColor Cyan
Write-Host "   Brave Shields - Filter List Diagnostics" -ForegroundColor Cyan
Write-Host " ============================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Launcher flags: is component update disabled? ------------------------

$launcherFiles = @("run.bat", "Launch.bat", "install.bat") | ForEach-Object { Join-Path $RootDir $_ }
$disabledLaunchers = @()
foreach ($lf in $launcherFiles) {
    if (Test-Path $lf) {
        $txt = Get-Content $lf -Raw
        if ($txt -match "--disable-component-update") { $disabledLaunchers += (Split-Path $lf -Leaf) }
    }
}

Write-Host " Launcher flags" -ForegroundColor Cyan
if ($disabledLaunchers.Count -gt 0) {
    Write-Err ("--disable-component-update found in: " + ($disabledLaunchers -join ", "))
    Write-Info "This flag stops Brave from downloading the default filter lists."
} else {
    Write-Ok "Component update is enabled (no --disable-component-update)."
}

# --- 2. Profile: does the adblock component cache exist? --------------------

function Get-ShieldsState {
    param([string]$Data)
    $result = [pscustomobject]@{
        Exists        = (Test-Path $Data)
        ComponentDirs = 0
        ListFiles     = 0
        CacheOk       = $false
        Paths         = @()
    }
    if (-not $result.Exists) { return $result }
    $dirs = @(Get-ChildItem $Data -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "adblock|ad_block" -or $_.FullName -match "\\adblock" })
    $result.ComponentDirs = $dirs.Count
    $result.Paths = @($dirs | ForEach-Object { $_.FullName })
    $files = @(Get-ChildItem $Data -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "adblock" })
    $result.ListFiles = $files.Count
    $result.CacheOk = ($result.ComponentDirs -gt 0 -and $result.ListFiles -gt 0)
    return $result
}

$state = Get-ShieldsState -Data $DataDir

Write-Host ""
Write-Host " Profile cache" -ForegroundColor Cyan
Write-Info "Data dir: $DataDir"
Write-Info ("Component dirs: {0}   Files: {1}" -f $state.ComponentDirs, $state.ListFiles)

if (-not $state.Exists) {
    Write-Warn2 "Data dir does not exist yet - run run.bat once, then re-check."
} elseif ($state.CacheOk) {
    Write-Ok "Adblock component cache present."
} else {
    Write-Warn2 "No adblock component cache yet (Shields lists not fetched)."
}

# --- Status mode ------------------------------------------------------------

if ($Status) {
    Write-Host ""
    if ($state.CacheOk -and $disabledLaunchers.Count -eq 0) {
        Write-Ok "Status: HEALTHY"
    } elseif ($disabledLaunchers.Count -gt 0) {
        Write-Warn2 "Status: BROKEN (--disable-component-update set)"
    } else {
        Write-Warn2 "Status: MISSING LISTS (needs a normal online launch)"
    }
    exit 0
}

# --- FixFlags mode: strip --disable-component-update from launchers ---------

if ($FixFlags) {
    Write-Host ""
    Write-Host " Fixing launcher flags" -ForegroundColor Cyan
    $fixed = 0
    foreach ($lf in $launcherFiles) {
        if (Test-Path $lf) {
            $txt = Get-Content $lf -Raw
            if ($txt -match "--disable-component-update") {
                $new = $txt -replace '\s*--disable-component-update', ''
                Set-Content -Path $lf -Value $new -NoNewline -Encoding ASCII
                $fixed++
                Write-Ok "Patched $(Split-Path $lf -Leaf)"
            }
        }
    }
    if ($fixed -eq 0) { Write-Info "Nothing to patch." }
    if (-not $Force) { exit 0 }
}

# --- Force mode: clear the adblock cache so the updater re-fetches it -------

if (-not $Force) {
    Write-Host ""
    Write-Info "Nothing changed. Options:"
    Write-Info "  -Status    diagnose only"
    Write-Info "  -FixFlags  remove --disable-component-update from .bat files"
    Write-Info "  -Force     clear the adblock cache so shields re-download lists"
    Write-Info "Then launch the browser ONLINE once and open brave://components."
    exit 0
}

Write-Host ""
Write-Host " Re-seeding the filter lists" -ForegroundColor Cyan

if (-not $state.Exists) {
    Write-Err "Data dir missing. Launch the browser once first."
    exit 1
}

# Refuse if the browser is running - it would rewrite the cache and/or lock it.
$running = @(Get-Process -Name "brave" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Err "Brave is running. Close it completely, then run -Force again."
    exit 1
}

$removed = 0
foreach ($p in $state.Paths) {
    try {
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
        $removed++
        Write-Ok "Cleared: $p"
    } catch {
        Write-Warn2 "Could not clear $p : $_"
    }
}

Write-Host ""
if ($removed -gt 0 -or $state.ComponentDirs -eq 0) {
    Write-Ok "Adblock cache cleared. Launch the browser online once."
    Write-Info "Brave will re-download the lists via the component updater."
    Write-Info "Verify afterwards: open brave://components -> 'Ad Block Updater'."
    Write-Info "Then: brave://adblock should list EasyList, Brave Default, etc."
} else {
    Write-Warn2 "Nothing was cleared (cache may be empty already)."
    Write-Info "Launch the browser online and watch brave://components."
}

Write-Host ""
exit 0
