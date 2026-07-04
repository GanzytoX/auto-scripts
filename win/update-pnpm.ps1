<#
.SYNOPSIS
    Automatically updates pnpm to the latest stable version on Windows.
.DESCRIPTION
    This script detects the installed version of pnpm, queries the latest stable version
    from the npm registry, and updates the binary using the original installation method
    (npm, standalone, or corepack).
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
    Write-Host "            AUTOMATIC PNPM UPDATER" -ForegroundColor $ColorPrimary
    Write-Host "=============================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Get-LatestPnpmVersion {
    try {
        $response = Invoke-RestMethod -Uri "https://registry.npmjs.org/pnpm/latest" -UseBasicParsing -TimeoutSec 8
        return $response.version
    }
    catch {
        Write-Host "[WARN] Could not retrieve version from npm registry. Checking connection..." -ForegroundColor $ColorWarning
        return $null
    }
}

function Get-CurrentPnpmVersion {
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpmCmd) {
        return $null
    }
    
    # Run pnpm --version silently
    try {
        $version = & pnpm --version 2>$null
        if ($version -match "^\d+\.\d+\.\d+") {
            return $version.Trim()
        }
    }
    catch {}
    return $null
}

function Detect-InstallationMethod {
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpmCmd) {
        return "None"
    }

    $path = $pnpmCmd.Source
    Write-Host "[Path] Detected path for pnpm: $path" -ForegroundColor $ColorMuted

    if ($path -like "*\Roaming\npm\*") {
        return "NPM"
    }
    elseif ($path -like "*\Local\pnpm\*") {
        return "Standalone"
    }
    elseif ($path -like "*\nodejs\pnpm*") {
        return "Corepack"
    }
    
    # Fallback checks based on available managers
    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        return "Corepack"
    }
    elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        return "NPM"
    }
    
    return "Standalone"
}

function Install-PnpmStandalone {
    Write-Host "[Install] Starting Standalone installation/update..." -ForegroundColor $ColorPrimary
    try {
        Invoke-RestMethod -Uri "https://get.pnpm.io/install.ps1" -UseBasicParsing | Invoke-Expression
        return $true
    }
    catch {
        Write-Host "[ERROR] Standalone installation error: $_" -ForegroundColor $ColorError
        return $false
    }
}

function Install-PnpmNpm {
    Write-Host "[Install] Starting update via NPM..." -ForegroundColor $ColorPrimary
    try {
        npm install -g pnpm@latest
        return $true
    }
    catch {
        Write-Host "[ERROR] Error updating via NPM: $_" -ForegroundColor $ColorError
        return $false
    }
}

function Install-PnpmCorepack {
    Write-Host "[Install] Starting update via Corepack..." -ForegroundColor $ColorPrimary
    try {
        corepack enable pnpm
        corepack prepare pnpm@latest --activate
        return $true
    }
    catch {
        Write-Host "[WARN] Corepack prepare failed. Retrying with npm install..." -ForegroundColor $ColorWarning
        return Install-PnpmNpm
    }
}

# --- Main Flow ---
Show-Header

Write-Host "[+] Querying the latest version of pnpm..." -ForegroundColor $ColorMuted
$LatestVersion = Get-LatestPnpmVersion
if (-not $LatestVersion) {
    Write-Host "[ERROR] Could not connect to the npm registry. Aborting update." -ForegroundColor $ColorError
    exit 1
}
Write-Host "[-] Latest available version: v$LatestVersion" -ForegroundColor $ColorPrimary

$CurrentVersion = Get-CurrentPnpmVersion
$Method = Detect-InstallationMethod

if (-not $CurrentVersion) {
    Write-Host "[INFO] pnpm is not installed on this system." -ForegroundColor $ColorWarning
    Write-Host "[NEW] Installing pnpm (version v$LatestVersion) for the first time..." -ForegroundColor $ColorSuccess
    
    $success = Install-PnpmStandalone
    if ($success) {
        Write-Host "[OK] pnpm installed successfully. Restart your terminal to apply changes." -ForegroundColor $ColorSuccess
    } else {
        Write-Host "[ERROR] Installation failed." -ForegroundColor $ColorError
    }
    exit
}

Write-Host "[-] Current version installed: v$CurrentVersion" -ForegroundColor $ColorPrimary
Write-Host "[-] Detected installation method: $Method" -ForegroundColor $ColorPrimary

# Compare versions
if ($CurrentVersion -eq $LatestVersion) {
    Write-Host "[OK] You already have the latest version installed! (v$CurrentVersion)" -ForegroundColor $ColorSuccess
    Write-Host "[OK] No update required." -ForegroundColor $ColorSuccess
    exit 0
}

Write-Host "[UPDATE] New version available. Updating from v$CurrentVersion to v$LatestVersion..." -ForegroundColor $ColorWarning

$success = $false
switch ($Method) {
    "NPM" {
        $success = Install-PnpmNpm
    }
    "Corepack" {
        $success = Install-PnpmCorepack
    }
    "Standalone" {
        $success = Install-PnpmStandalone
    }
    Default {
        $success = Install-PnpmStandalone
    }
}

if ($success) {
    # Attempt to refresh the Path environment variable in the current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    $NewVersion = Get-CurrentPnpmVersion
    if ($NewVersion -eq $LatestVersion) {
        Write-Host "[SUCCESS] Update successful! You are now on version v$NewVersion." -ForegroundColor $ColorSuccess
    } else {
        Write-Host "[OK] Installation process completed." -ForegroundColor $ColorSuccess
        Write-Host "[WARN] If the version shown is still the old one in this terminal, please open a new terminal window to apply changes." -ForegroundColor $ColorWarning
    }
} else {
    Write-Host "[ERROR] Something went wrong while updating pnpm." -ForegroundColor $ColorError
}
