<#
.SYNOPSIS
    Lists all globally installed packages for npm and pnpm on Windows.
.DESCRIPTION
    This script queries npm and pnpm for globally installed packages
    and displays them in a clean, formatted table with premium terminal colors.
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
    Write-Host "         GLOBAL NODE.JS PACKAGES LIST" -ForegroundColor $ColorPrimary
    Write-Host "=============================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Get-NpmGlobalPackages {
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        Write-Host "[-] NPM: Not installed or not found in PATH." -ForegroundColor $ColorWarning
        Write-Host ""
        return
    }

    Write-Host "[+] Querying NPM global packages..." -ForegroundColor $ColorMuted
    try {
        # Run npm list and capture JSON. Redirect stderr to avoid parsing warnings.
        $jsonStr = & npm list -g --depth=0 --json 2>$null | Out-String
        if ($jsonStr -and $jsonStr.Trim()) {
            $data = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($data -and $data.dependencies) {
                Write-Host "--- NPM Global Packages ---" -ForegroundColor $ColorPrimary
                Write-Host ("{0,-40} {1}" -f "Package Name", "Version") -ForegroundColor $ColorPrimary
                Write-Host ("{0,-40} {1}" -f "------------", "-------") -ForegroundColor $ColorMuted
                
                $count = 0
                foreach ($name in $data.dependencies.psobject.properties.Name) {
                    $pkgInfo = $data.dependencies.$name
                    $version = $pkgInfo.version
                    if (-not $version -and $pkgInfo.resolved) {
                        $version = "installed"
                    }
                    Write-Host ("{0,-40} " -f $name) -NoNewline -ForegroundColor $ColorSuccess
                    Write-Host $version -ForegroundColor $ColorMuted
                    $count++
                }
                Write-Host ("{0,-40} {1}" -f "------------", "-------") -ForegroundColor $ColorMuted
                Write-Host "Total NPM packages: $count" -ForegroundColor $ColorSuccess
            } else {
                Write-Host "No global NPM packages found." -ForegroundColor $ColorMuted
            }
        } else {
            Write-Host "[WARN] Could not retrieve packages from NPM." -ForegroundColor $ColorWarning
        }
    }
    catch {
        Write-Host "[ERROR] Failed to query NPM global packages: $_" -ForegroundColor $ColorError
    }
    Write-Host ""
}

function Get-PnpmGlobalPackages {
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpmCmd) {
        Write-Host "[-] PNPM: Not installed or not found in PATH." -ForegroundColor $ColorWarning
        Write-Host ""
        return
    }

    Write-Host "[+] Querying PNPM global packages..." -ForegroundColor $ColorMuted
    try {
        # Check output/errors from pnpm list -g
        $testRun = & pnpm list -g --depth 0 --json 2>&1
        $testOut = $testRun | Out-String
        
        if ($testOut -like "*is not in PATH*" -or $testOut -like "*pnpm setup*") {
            Write-Host "[WARN] PNPM global bin directory is not in your PATH." -ForegroundColor $ColorWarning
            Write-Host "       Run 'pnpm setup' to configure the global bin directory." -ForegroundColor $ColorWarning
            Write-Host ""
            return
        }

        if ($testOut -and $testOut.Trim()) {
            $data = $testOut | ConvertFrom-Json -ErrorAction SilentlyContinue
            $count = 0
            $hasPrintedHeader = $false

            if ($data) {
                foreach ($item in $data) {
                    if ($item.dependencies) {
                        if (-not $hasPrintedHeader) {
                            Write-Host "--- PNPM Global Packages ---" -ForegroundColor $ColorPrimary
                            Write-Host ("{0,-40} {1}" -f "Package Name", "Version") -ForegroundColor $ColorPrimary
                            Write-Host ("{0,-40} {1}" -f "------------", "-------") -ForegroundColor $ColorMuted
                            $hasPrintedHeader = $true
                        }

                        foreach ($name in $item.dependencies.psobject.properties.Name) {
                            $pkgInfo = $item.dependencies.$name
                            $version = $pkgInfo.version
                            Write-Host ("{0,-40} " -f $name) -NoNewline -ForegroundColor $ColorSuccess
                            Write-Host $version -ForegroundColor $ColorMuted
                            $count++
                        }
                    }
                }
            }

            if ($hasPrintedHeader) {
                Write-Host ("{0,-40} {1}" -f "------------", "-------") -ForegroundColor $ColorMuted
                Write-Host "Total PNPM packages: $count" -ForegroundColor $ColorSuccess
            } else {
                Write-Host "No global PNPM packages found." -ForegroundColor $ColorMuted
            }
        } else {
            Write-Host "[WARN] Could not retrieve packages from PNPM." -ForegroundColor $ColorWarning
        }
    }
    catch {
        Write-Host "[ERROR] Failed to query PNPM global packages: $_" -ForegroundColor $ColorError
    }
    Write-Host ""
}

# --- Main Flow ---
Show-Header
Get-NpmGlobalPackages
Get-PnpmGlobalPackages
Write-Host "=============================================" -ForegroundColor $ColorPrimary
