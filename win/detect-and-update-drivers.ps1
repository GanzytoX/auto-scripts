<#
.SYNOPSIS
    Scans all computer hardware devices
    and checks/installs driver updates from Windows Update.
.DESCRIPTION
    This script queries connected devices using PnpDevice, searches for driver
    updates using the native Windows Update API, and allows interactive installations.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Premium terminal colors
$ColorPrimary = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"
$ColorMuted = "Gray"
$ColorInfo = "White"

function Show-Header {
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor $ColorPrimary
    Write-Host "         TOTAL DRIVER DETECTOR AND MANAGER" -ForegroundColor $ColorPrimary
    Write-Host "=========================================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Main Script Flow ---

Show-Header

# 1. Verify Privilege Elevation
$IsAdmin = Test-IsAdmin
if (-not $IsAdmin) {
    Write-Host "[WARNING] You are not running this script as Administrator." -ForegroundColor $ColorWarning
    Write-Host "          Installing drivers requires elevated privileges." -ForegroundColor $ColorWarning
    Write-Host ""
    Write-Host "Do you want to restart this script as Administrator automatically? [Y] Yes / [N] No: " -NoNewline -ForegroundColor $ColorInfo
    
    $key = $null
    try {
        $response = [Console]::ReadKey($true)
        $key = $response.KeyChar.ToString().ToUpper()
        Write-Host $key -ForegroundColor $ColorPrimary
    }
    catch {
        $resp = Read-Host
        $key = $resp.Trim().ToUpper()
    }
    
    if ($key -eq "Y" -or $key -eq "`r" -or $key -eq "`n") {
        Write-Host ""
        Write-Host "[+] Restarting as Administrator..." -ForegroundColor $ColorSuccess
        try {
            $psPath = (Get-Process -Id $PID).Path
            Start-Process $psPath -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
            exit
        }
        catch {
            Write-Host "[ERROR] Could not elevate privileges: $_" -ForegroundColor $ColorError
            Write-Host "Continuing in non-administrator mode..." -ForegroundColor $ColorMuted
            Write-Host ""
        }
    } else {
        Write-Host ""
        Write-Host "Continuing in non-administrator mode..." -ForegroundColor $ColorMuted
        Write-Host ""
    }
}

# 2. Scan Hardware
Write-Host "[+] Starting hardware scan of your laptop... Please wait." -ForegroundColor $ColorPrimary
Write-Host ""

Write-Host "[-] Detecting connected devices... " -NoNewline -ForegroundColor $ColorInfo
$pnpDevices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
Write-Host "Done ($($pnpDevices.Count) devices detected)" -ForegroundColor $ColorSuccess

# Classification by class
$grouped = $pnpDevices | Group-Object Class -NoElement | Sort-Object Count -Descending
Write-Host ""
Write-Host "Hardware summary by category:" -ForegroundColor $ColorMuted
foreach ($grp in $grouped) {
    if ($grp.Name) {
        Write-Host "    -> $($grp.Name): $($grp.Count)" -ForegroundColor $ColorInfo
    }
}
Write-Host ""

# 3. Check for driver updates
Write-Host "[+] Checking for outdated drivers in Windows Update..." -ForegroundColor $ColorPrimary
Write-Host "    (This may take a moment, querying official servers)..." -ForegroundColor $ColorMuted
Write-Host ""

$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()

# Filter for uninstalled drivers
try {
    $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")
    $allUpgrades = $searchResult.Updates
}
catch {
    Write-Host "[ERROR] There was a problem checking for updates: $_" -ForegroundColor $ColorError
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor $ColorMuted
    try { [void][Console]::ReadKey($true) } catch { Read-Host }
    exit 1
}

if ($allUpgrades.Count -eq 0) {
    Write-Host "[OK] Congratulations! All drivers on your laptop are up to date." -ForegroundColor $ColorSuccess
    Write-Host ""
    
    $viewAll = Read-Host "Do you want to see the full list of all detected hardware devices? (Y/N)"
    if ($viewAll.Trim().ToUpper() -eq "Y") {
        Write-Host ""
        Write-Host ("{0,-60} {1,-20} {2}" -f "Device Name", "Category", "Status") -ForegroundColor $ColorPrimary
        Write-Host ("{0,-60} {1,-20} {2}" -f "-----------", "--------", "------") -ForegroundColor $ColorMuted
        foreach ($dev in $pnpDevices | Sort-Object FriendlyName) {
            $displayName = $dev.FriendlyName
            if ($displayName.Length -gt 57) { $displayName = $displayName.Substring(0, 54) + "..." }
            Write-Host ("{0,-60} {1,-20} " -f $displayName, $dev.Class) -NoNewline
            Write-Host $dev.Status -ForegroundColor $ColorSuccess
        }
    }
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor $ColorMuted
    try { [void][Console]::ReadKey($true) } catch { Read-Host }
    exit 0
}

# List outdated drivers
Write-Host "Found $($allUpgrades.Count) available driver updates:" -ForegroundColor $ColorWarning
Write-Host ""
Write-Host ("{0,-65} {1,-15} {2}" -f "Driver Name / Update", "Max Size", "Source") -ForegroundColor $ColorPrimary
Write-Host ("{0,-65} {1,-15} {2}" -f "--------------------", "--------", "------") -ForegroundColor $ColorMuted

foreach ($upg in $allUpgrades) {
    $displayName = $upg.Title
    if ($displayName.Length -gt 62) { $displayName = $displayName.Substring(0, 59) + "..." }
    
    # Calculate size
    $sizeMB = [Math]::Round($upg.MaxDownloadSize / 1MB, 2)
    $sizeText = "$sizeMB MB"
    if ($sizeMB -lt 0.1) {
        $sizeKB = [Math]::Round($upg.MaxDownloadSize / 1KB, 2)
        $sizeText = "$sizeKB KB"
    }
    
    Write-Host ("{0,-65} {1,-15} " -f $displayName, $sizeText) -NoNewline
    Write-Host "Windows Update" -ForegroundColor $ColorWarning
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host " STARTING INTERACTIVE DRIVER UPDATE FLOW" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

$autoUpdateAll = $false
$rebootRequired = $false

foreach ($upg in $allUpgrades) {
    $action = "No"
    
    if (-not $autoUpdateAll) {
        while ($true) {
            Write-Host ""
            Write-Host ">>> Do you want to update the driver: " -NoNewline
            Write-Host $upg.Title -ForegroundColor $ColorPrimary
            Write-Host "    [Y] Yes  [N] No  [A] Install all without asking  [C] Cancel and Exit: " -NoNewline -ForegroundColor $ColorInfo
            
            $key = $null
            try {
                $response = [Console]::ReadKey($true)
                $key = $response.KeyChar.ToString().ToUpper()
                Write-Host $key -ForegroundColor $ColorPrimary
            }
            catch {
                $resp = Read-Host
                $key = $resp.Trim().ToUpper()
            }
            
            if ($key -eq "Y" -or $key -eq "`r" -or $key -eq "`n") {
                $action = "Yes"
                break
            } elseif ($key -eq "N") {
                $action = "No"
                break
            } elseif ($key -eq "A") {
                $action = "All"
                break
            } elseif ($key -eq "C") {
                $action = "Cancel"
                break
            } else {
                Write-Host "[!] Invalid option. Press Y, N, A, or C." -ForegroundColor $ColorWarning
            }
        }
    } else {
        $action = "Yes"
    }
    
    if ($action -eq "Cancel") {
        Write-Host ""
        Write-Host "[!] Update process cancelled. Exiting..." -ForegroundColor $ColorWarning
        break
    }
    
    if ($action -eq "All") {
        $autoUpdateAll = $true
        $action = "Yes"
        Write-Host "[+] Bulk driver installation mode activated..." -ForegroundColor $ColorWarning
    }
    
    if ($action -eq "Yes") {
        Write-Host ""
        Write-Host "[+] Downloading driver: $($upg.Title)... " -NoNewline -ForegroundColor $ColorPrimary
        
        $updateCollection = New-Object -ComObject Microsoft.Update.UpdateColl
        $updateCollection.Add($upg)
        
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updateCollection
        
        try {
            $downloadResult = $downloader.Download()
            if ($downloadResult.ResultCode -eq 2) {
                Write-Host "Completed." -ForegroundColor $ColorSuccess
                
                Write-Host "[+] Installing driver: $($upg.Title)... " -NoNewline -ForegroundColor $ColorPrimary
                $installer = $updateSession.CreateUpdateInstaller()
                $installer.Updates = $updateCollection
                
                $installResult = $installer.Install()
                if ($installResult.ResultCode -eq 2) {
                    Write-Host "Installed." -ForegroundColor $ColorSuccess
                    if ($installResult.RebootRequired) {
                        Write-Host "[!] WARNING: This driver requires a system restart." -ForegroundColor $ColorWarning
                        $rebootRequired = $true
                    } else {
                        Write-Host "[SUCCESS] Driver installed successfully." -ForegroundColor $ColorSuccess
                    }
                } else {
                    Write-Host "Installation error (Code: $($installResult.ResultCode))." -ForegroundColor $ColorError
                }
            } else {
                Write-Host "Download error (Code: $($downloadResult.ResultCode))." -ForegroundColor $ColorError
            }
        }
        catch {
            Write-Host "Unexpected error while downloading/installing: $_" -ForegroundColor $ColorError
        }
    }
    else {
        Write-Host "[-] Skipping driver." -ForegroundColor $ColorMuted
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host "               PROCESS COMPLETED" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

if ($rebootRequired) {
    Write-Host "[!] IMPORTANT: Installed drivers require a system restart." -ForegroundColor $ColorWarning
    Write-Host "Do you want to restart the computer right now? [Y] Yes / [N] No: " -NoNewline -ForegroundColor $ColorInfo
    
    $key = $null
    try {
        $response = [Console]::ReadKey($true)
        $key = $response.KeyChar.ToString().ToUpper()
        Write-Host $key -ForegroundColor $ColorPrimary
    }
    catch {
        $resp = Read-Host
        $key = $resp.Trim().ToUpper()
    }
    
    if ($key -eq "Y" -or $key -eq "`r" -or $key -eq "`n") {
        Write-Host ""
        Write-Host "[+] Restarting system in 5 seconds..." -ForegroundColor $ColorSuccess
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit
    } else {
        Write-Host ""
        Write-Host "[-] Remember to restart your laptop manually as soon as possible." -ForegroundColor $ColorWarning
    }
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor $ColorMuted
try { [void][Console]::ReadKey($true) } catch { Read-Host }
