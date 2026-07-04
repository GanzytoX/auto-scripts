<#
.SYNOPSIS
    Displays detailed information about Node.js and its environment on Windows.
.DESCRIPTION
    This script gathers local information (Node version, path, V8, UV, OpenSSL, npm, pnpm)
    and fetches the latest available LTS and Current versions from the official Node.js registry.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Premium terminal coloring
$ColorPrimary = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"
$ColorMuted = "Gray"

function Show-Header {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor $ColorPrimary
    Write-Host "             NODE.JS ENVIRONMENT INFO" -ForegroundColor $ColorPrimary
    Write-Host "=============================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Get-LatestNodeVersions {
    try {
        $releases = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing -TimeoutSec 8
        if ($releases) {
            $latestCurrent = $releases[0].version
            $latestLtsItem = $releases | Where-Object { $_.lts -ne $false } | Select-Object -First 1
            return @{
                Current = $latestCurrent
                Lts = $latestLtsItem.version
                LtsCodename = $latestLtsItem.lts
            }
        }
    }
    catch {
        # Silent error, will fall back
    }
    return $null
}

function Get-InstalledNodeWingetId {
    $candidateIds = @(
        "OpenJS.NodeJS.LTS",
        "OpenJS.NodeJS"
    )

    foreach ($candidateId in $candidateIds) {
        try {
            $result = & winget list --id $candidateId --exact 2>$null | Out-String
            if ($result -match [regex]::Escape($candidateId)) {
                return $candidateId
            }
        }
        catch {}
    }

    return $null
}

function Invoke-NodeWingetUpdate {
    $wingetId = Get-InstalledNodeWingetId
    if (-not $wingetId) {
        Write-Host "[WARN] Winget did not detect an installed Node.js package that it can upgrade." -ForegroundColor $ColorWarning
        Write-Host "[WARN] Automatic update is only available when Node.js was installed with Winget." -ForegroundColor $ColorWarning
        return $false
    }

    Write-Host "[UPDATE] Winget detected package: $wingetId" -ForegroundColor $ColorWarning
    Write-Host "[UPDATE] Running automatic upgrade with Winget..." -ForegroundColor $ColorWarning

    try {
        & winget upgrade --id $wingetId --exact --silent --accept-package-agreements --accept-source-agreements

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        return $true
    }
    catch {
        Write-Host "[ERROR] Winget could not update Node.js: $_" -ForegroundColor $ColorError
        return $false
    }
}

# --- Main Flow ---
Show-Header

# 1. Local Node.js Check
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host "[ERROR] Node.js is not installed or not found in your PATH." -ForegroundColor $ColorError
    Write-Host "[INFO] Download and install it from: https://nodejs.org/" -ForegroundColor $ColorWarning
    exit 1
}

$localVersion = (node -v 2>$null).Trim()
$localArch = (node -p "process.arch" 2>$null).Trim()
$localPlatform = (node -p "process.platform" 2>$null).Trim()
$v8Version = (node -p "process.versions.v8" 2>$null).Trim()
$uvVersion = (node -p "process.versions.uv" 2>$null).Trim()
$opensslVersion = (node -p "process.versions.openssl" 2>$null).Trim()

$wingetUpdateDone = $false

# Gather npm and pnpm versions if available
$npmVersion = "Not installed"
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    $npmVersion = (npm -v 2>$null).Trim()
}

$pnpmVersion = "Not installed"
$pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
if ($pnpmCmd) {
    $pnpmVersion = (pnpm -v 2>$null).Trim()
}

# Print local stats
Write-Host "--- Local Environment ---" -ForegroundColor $ColorPrimary
Write-Host "Node.js Version:  $localVersion ($localPlatform $localArch)" -ForegroundColor $ColorSuccess
Write-Host "Executable Path:  $($nodeCmd.Source)" -ForegroundColor $ColorMuted
Write-Host "V8 Engine:        $v8Version" -ForegroundColor $ColorMuted
Write-Host "libuv Version:    $uvVersion" -ForegroundColor $ColorMuted
Write-Host "OpenSSL Version:  $opensslVersion" -ForegroundColor $ColorMuted
Write-Host "npm Version:      $npmVersion" -ForegroundColor $ColorMuted
Write-Host "pnpm Version:     $pnpmVersion" -ForegroundColor $ColorMuted
Write-Host ""

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "[+] Checking if Winget can update Node.js automatically..." -ForegroundColor $ColorMuted
    $wingetUpdateDone = Invoke-NodeWingetUpdate

    if ($wingetUpdateDone) {
        $localVersion = (node -v 2>$null).Trim()
        $localArch = (node -p "process.arch" 2>$null).Trim()
        $localPlatform = (node -p "process.platform" 2>$null).Trim()
        $v8Version = (node -p "process.versions.v8" 2>$null).Trim()
        $uvVersion = (node -p "process.versions.uv" 2>$null).Trim()
        $opensslVersion = (node -p "process.versions.openssl" 2>$null).Trim()
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $npmVersion = (npm -v 2>$null).Trim()
        }

        $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
        if ($pnpmCmd) {
            $pnpmVersion = (pnpm -v 2>$null).Trim()
        }

        Write-Host ""
        Write-Host "[OK] Node.js update check completed. Refreshing the reported local version below." -ForegroundColor $ColorSuccess
        Write-Host "--- Updated Local Environment ---" -ForegroundColor $ColorPrimary
        Write-Host "Node.js Version:  $localVersion ($localPlatform $localArch)" -ForegroundColor $ColorSuccess
        Write-Host "Executable Path:  $($nodeCmd.Source)" -ForegroundColor $ColorMuted
        Write-Host "V8 Engine:        $v8Version" -ForegroundColor $ColorMuted
        Write-Host "libuv Version:    $uvVersion" -ForegroundColor $ColorMuted
        Write-Host "OpenSSL Version:  $opensslVersion" -ForegroundColor $ColorMuted
        Write-Host "npm Version:      $npmVersion" -ForegroundColor $ColorMuted
        Write-Host "pnpm Version:     $pnpmVersion" -ForegroundColor $ColorMuted
        Write-Host ""
    }
}

# 2. Remote check for updates
Write-Host "[+] Querying nodejs.org for latest releases..." -ForegroundColor $ColorMuted
$remoteVersions = Get-LatestNodeVersions

if ($remoteVersions) {
    Write-Host ""
    Write-Host "--- Latest Available Releases ---" -ForegroundColor $ColorPrimary
    Write-Host "Latest LTS (Recommended):  $($remoteVersions.Lts) ($($remoteVersions.LtsCodename))" -ForegroundColor $ColorSuccess
    Write-Host "Latest Current (Features): $($remoteVersions.Current)" -ForegroundColor $ColorPrimary
    Write-Host ""

    # Check if local is out of date compared to LTS or Current
    # Normalize versions by removing 'v'
    $localClean = $localVersion -replace 'v', ''
    $ltsClean = $remoteVersions.Lts -replace 'v', ''
    $currentClean = $remoteVersions.Current -replace 'v', ''

    $localObj = [System.Version]$localClean
    $ltsObj = [System.Version]$ltsClean
    $currentObj = [System.Version]$currentClean

    if ($localObj -lt $ltsObj) {
        Write-Host "[UPDATE] Your Node.js version ($localVersion) is older than the recommended LTS version ($($remoteVersions.Lts))." -ForegroundColor $ColorWarning
        Write-Host "[UPDATE] It is highly recommended to update Node.js by downloading the latest installer." -ForegroundColor $ColorWarning
    }
    elseif ($localObj -lt $currentObj) {
        Write-Host "[INFO] A newer Current version ($($remoteVersions.Current)) is available if you want the latest features." -ForegroundColor $ColorWarning
    }
    else {
        Write-Host "[OK] Your Node.js installation is fully up to date." -ForegroundColor $ColorSuccess
    }
} else {
    Write-Host "[WARN] Could not connect to nodejs.org to check for updates." -ForegroundColor $ColorWarning
}
Write-Host "=============================================" -ForegroundColor $ColorPrimary
