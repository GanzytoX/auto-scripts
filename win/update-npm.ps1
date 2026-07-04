<#
.SYNOPSIS
    Automatically updates npm to the latest stable version on Windows.
.DESCRIPTION
    This script detects the installed version of npm, queries the latest stable version
    from the npm registry, and updates npm globally if a new version is available.
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
    Write-Host "             AUTOMATIC NPM UPDATER" -ForegroundColor $ColorPrimary
    Write-Host "=============================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Get-LatestNpmVersion {
    try {
        $response = Invoke-RestMethod -Uri "https://registry.npmjs.org/npm/latest" -UseBasicParsing -TimeoutSec 8
        return $response.version
    }
    catch {
        Write-Host "[WARN] Could not retrieve version from npm registry. Checking connection..." -ForegroundColor $ColorWarning
        return $null
    }
}

function Get-CurrentNpmVersion {
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        return $null
    }
    
    # Run npm --version silently
    try {
        $version = & npm --version 2>$null
        if ($version -match "^\d+\.\d+\.\d+") {
            return $version.Trim()
        }
    }
    catch {}
    return $null
}

# --- Main Flow ---
Show-Header

Write-Host "[+] Querying the latest version of npm..." -ForegroundColor $ColorMuted
$LatestVersion = Get-LatestNpmVersion
if (-not $LatestVersion) {
    Write-Host "[ERROR] Could not connect to the npm registry. Aborting update." -ForegroundColor $ColorError
    exit 1
}
Write-Host "[-] Latest available version: v$LatestVersion" -ForegroundColor $ColorPrimary

$CurrentVersion = Get-CurrentNpmVersion

if (-not $CurrentVersion) {
    Write-Host "[ERROR] npm is not installed or not found in your PATH." -ForegroundColor $ColorError
    Write-Host "[INFO] Please install Node.js (which includes npm) from https://nodejs.org/" -ForegroundColor $ColorWarning
    exit 1
}

Write-Host "[-] Current version installed: v$CurrentVersion" -ForegroundColor $ColorPrimary

# Compare versions
if ($CurrentVersion -eq $LatestVersion) {
    Write-Host "[OK] You already have the latest version installed! (v$CurrentVersion)" -ForegroundColor $ColorSuccess
    Write-Host "[OK] No update required." -ForegroundColor $ColorSuccess
    exit 0
}

Write-Host "[UPDATE] New version available. Updating from v$CurrentVersion to v$LatestVersion..." -ForegroundColor $ColorWarning

Write-Host "[Install] Running: npm install -g npm@latest" -ForegroundColor $ColorPrimary
try {
    # Run npm update command
    npm install -g npm@latest
    
    # Attempt to refresh the Path environment variable in the current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    $NewVersion = Get-CurrentNpmVersion
    if ($NewVersion -eq $LatestVersion) {
        Write-Host "[SUCCESS] Update successful! You are now on version v$NewVersion." -ForegroundColor $ColorSuccess
    } else {
        Write-Host "[OK] Installation process completed." -ForegroundColor $ColorSuccess
        Write-Host "[WARN] If the version shown is still the old one in this terminal, please open a new terminal window to apply changes." -ForegroundColor $ColorWarning
    }
}
catch {
    Write-Host "[ERROR] Something went wrong while updating npm: $_" -ForegroundColor $ColorError
}
