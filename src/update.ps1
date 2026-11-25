# BraveOriginFree - Update (self-updating, no prompts)
#
# Downloads the newest BraveOriginFree package built by this project's own
# GitHub Actions workflow and installs it in place. That package already
# contains bin\ (the Brave Origin binary), the launchers and a pre-applied
# Local State, so nothing is compiled locally. Rollback to bin.bak on failure.
#
# Only fall back to fetching the raw Brave Origin zip when no BraveOriginFree
# release exists yet (fresh repo/brand-new install).

param([switch]$CheckOnly, [int]$ScanDepth = 40)

$ErrorActionPreference = "Stop"

$AppDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $AppDir
$BinDir    = Join-Path $RootDir "bin"
$DataDir   = Join-Path $RootDir "data"
$OriginExe = Join-Path $BinDir "brave.exe"
$VersionFile = Join-Path $RootDir "version.txt"
$OwnRepo   = "6zev/BraveOriginFree"
$ApiBase   = "https://api.github.com/repos/$OwnRepo"
$BraveApi  = "https://api.github.com/repos/brave/brave-browser"

function Get-CurrentVersion {
    if (Test-Path $VersionFile) {
        $v = (Get-Content $VersionFile -Raw).Trim()
        if ($v) { return $v }
    }
    if (Test-Path $OriginExe) {
        try { return (Get-Item $OriginExe).VersionInfo.FileVersion } catch {}
    }
    return "unknown"
}

function Test-Newer($a, $b) {
    try { return ([version]$a -gt [version]$b) } catch { return ($a -ne $b) }
}

function Get-ApiJson($url) {
    $ProgressPreference = 'SilentlyContinue'
    return (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30 -Headers @{
        'User-Agent' = 'BraveOriginFree-Updater'
        'Accept'     = 'application/vnd.github+json'
    }).Content | ConvertFrom-Json
}

# A BraveOriginFree release ships BraveOriginFree-v<v>.zip at the repo root
# of the archive (already assembled), so it is a drop-in replacement.
function Find-LatestPackage {
    $releases = Get-ApiJson "$ApiBase/releases?per_page=$ScanDepth"
    $candidates = @()
    foreach ($r in $releases) {
        $pkg = $r.assets | Where-Object { $_.name -match '^BraveOriginFree-v[0-9.]+\.zip$' } | Select-Object -First 1
        if ($null -eq $pkg) { continue }
        $ver = $r.tag_name -replace '^v', ''
        $candidates += [pscustomobject]@{
            Version = $ver
            Url     = $pkg.browser_download_url
            Name    = $pkg.name
            Layout  = 'package'
        }
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object { try { [version]$_.Version } catch { [version]'0.0.0' } } -Descending | Select-Object -First 1)
}

# Fallback: no BraveOriginFree release yet -> take the raw Brave Origin build.
function Find-LatestOrigin {
    $releases = Get-ApiJson "$BraveApi/releases?per_page=$ScanDepth"
    $candidates = @()
    foreach ($r in $releases) {
        $zipAsset = $r.assets | Where-Object { $_.name -match '^brave-origin-v[0-9.]+-win32-x64\.zip$' } | Select-Object -First 1
        if ($null -eq $zipAsset) { continue }
        $ver = $r.tag_name -replace '^v', ''
        $candidates += [pscustomobject]@{
            Version = $ver
            Url     = $zipAsset.browser_download_url
            Name    = $zipAsset.name
            Layout  = 'origin'
        }
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object { try { [version]$_.Version } catch { [version]'0.0.0' } } -Descending | Select-Object -First 1)
}

Write-Host "BraveOriginFree - Update" -ForegroundColor Cyan
Write-Host ""

$current = Get-CurrentVersion
Write-Host "Installed: v$current" -ForegroundColor Gray

Write-Host "Checking for updates..." -ForegroundColor Yellow
try {
    $target = Find-LatestPackage
    if ($null -eq $target) {
        Write-Host "No BraveOriginFree release published yet - falling back to the raw Brave Origin build." -ForegroundColor DarkYellow
        $target = Find-LatestOrigin
    }
} catch {
    Write-Host "Could not reach GitHub: $_" -ForegroundColor Red
    exit 1
}

if ($null -eq $target) {
    Write-Host "No update source found in the last $ScanDepth releases." -ForegroundColor Red
    exit 1
}

$latest = $target.Version
Write-Host "Latest:    v$latest" -ForegroundColor Gray

if (-not (Test-Newer $latest $current)) {
    Write-Host "Already up to date." -ForegroundColor Green
    exit 0
}

Write-Host "Update available: v$current -> v$latest" -ForegroundColor Yellow
if ($CheckOnly) { exit 0 }

# --- Download ---------------------------------------------------------------

$zipName = $target.Name
$zipPath = Join-Path $RootDir $zipName
$staging = Join-Path $RootDir "_update.tmp"
Write-Host "Downloading $zipName ..." -ForegroundColor Yellow
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $target.Url -OutFile $zipPath -UseBasicParsing -TimeoutSec 900
} catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    exit 1
}

# --- Unpack to staging ------------------------------------------------------
# Unpack first and only swap when the result looks usable, so a corrupt
# download never leaves the install without a browser.

if (Test-Path $staging) { Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue }
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $staging -Force
} catch {
    Write-Host "Extraction failed: $_" -ForegroundColor Red
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    exit 1
}
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

$stagedBin = Join-Path $staging "bin"
if (-not (Test-Path (Join-Path $stagedBin "brave.exe"))) {
    Write-Host "Downloaded archive has no bin\brave.exe - aborting." -ForegroundColor Red
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
    exit 1
}

# --- Swap in ----------------------------------------------------------------

$backup = Join-Path $RootDir "bin.bak"
if (Test-Path $backup) { Remove-Item -Recurse -Force $backup -ErrorAction SilentlyContinue }
if (Test-Path $BinDir) {
    try {
        Move-Item $BinDir $backup -Force
        Write-Host "Backed up old build to bin.bak" -ForegroundColor Gray
    } catch {
        Write-Host "Could not back up bin\: $_" -ForegroundColor Red
        Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
        exit 1
    }
}

try {
    Move-Item $stagedBin $BinDir -Force
    # A BraveOriginFree package also carries refreshed launchers and helpers.
    if ($target.Layout -eq 'package') {
        foreach ($item in @('install.bat','run.bat','Launch.bat','CheckUpdate.bat','FixShields.bat','MakeDefault.bat','make-default.ps1','README.md','CHANGELOG.md')) {
            $srcItem = Join-Path $staging $item
            if (Test-Path $srcItem) { Copy-Item $srcItem -Destination $RootDir -Force }
        }
        $srcDir = Join-Path $staging "src"
        if (Test-Path $srcDir) { Copy-Item (Join-Path $srcDir '*') -Destination $AppDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Set-Content -Path $VersionFile -Value $latest -Encoding ASCII -NoNewline
    Write-Host "Updated to v$latest" -ForegroundColor Green
} catch {
    Write-Host "Install failed: $_" -ForegroundColor Red
    Remove-Item -Recurse -Force $BinDir -ErrorAction SilentlyContinue
    if (Test-Path $backup) { Move-Item $backup $BinDir -Force }
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $backup -ErrorAction SilentlyContinue

# --- Re-apply activation ----------------------------------------------------

$LocalState = Join-Path $DataDir "Local State"
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
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
Write-Host "Done. v$latest is ready - run run.bat." -ForegroundColor Cyan
