<#
.SYNOPSIS
    Checks and optionally installs driver updates from Windows Update.
.DESCRIPTION
    The default mode is read-only. -Update requests installation, -Yes confirms all
    updates non-interactively, and -Restart explicitly permits a required restart.
#>

[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Yes,
    [switch]$ListDevices,
    [switch]$Restart
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

if ($Yes -and -not $Update) {
    Write-ErrorMessage "-Yes can only be used together with -Update."
    exit 2
}
if ($Restart -and -not $Update) {
    Write-ErrorMessage "-Restart can only be used together with -Update."
    exit 2
}

if ($env:OS -ne 'Windows_NT') {
    Write-ErrorMessage "This script can only run on Windows."
    exit 1
}

function Start-ElevatedDriverManager {
    $powerShellPath = (Get-Process -Id $PID).Path
    $arguments = @('-NoProfile', '-File', ('"{0}"' -f $PSCommandPath), '-Update')
    if ($Yes) { $arguments += '-Yes' }
    if ($ListDevices) { $arguments += '-ListDevices' }
    if ($Restart) { $arguments += '-Restart' }

    try {
        $process = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
        return $process.ExitCode
    }
    catch {
        Write-ErrorMessage "Administrator elevation failed or was cancelled: $($_.Exception.Message)"
        return 1
    }
}

function Get-DriverUpdates {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Driver'")

    $updates = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $result.Updates.Count; $index++) {
        $updates.Add($result.Updates.Item($index))
    }

    return [PSCustomObject]@{
        Session = $session
        Updates = @($updates)
    }
}

function Show-DeviceInventory {
    if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        Write-WarningMessage "Get-PnpDevice is unavailable; the hardware inventory was skipped."
        return
    }

    Write-Section "--- Present hardware devices ---"
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Sort-Object Class, FriendlyName)
    if ($devices.Count -eq 0) {
        Write-WarningMessage "No present devices could be enumerated."
        return
    }

    $devices |
        Select-Object @{N='Device'; E={ if ($_.FriendlyName) { $_.FriendlyName } else { $_.InstanceId } }}, Class, Status |
        Format-Table -AutoSize
    Write-Success "Present devices detected: $($devices.Count)"
    Write-Host ""
}

Write-Section "=== Windows Driver Updates ==="
Write-Host ""

if ($ListDevices) {
    Show-DeviceInventory
}

if ($Update -and -not (Test-IsAdministrator)) {
    if (-not (Confirm-Action -Prompt "Driver installation requires Administrator privileges. Restart this script elevated?" -Yes:$Yes)) {
        Write-Success "No drivers were changed."
        exit 0
    }
    exit (Start-ElevatedDriverManager)
}

Write-Host "Checking Windows Update for driver updates..." -ForegroundColor $script:ColorMuted
try {
    $driverState = Get-DriverUpdates
}
catch {
    Write-ErrorMessage "Windows Update could not search for drivers: $($_.Exception.Message)"
    exit 1
}

$driverUpdates = @($driverState.Updates)
if ($driverUpdates.Count -eq 0) {
    Write-Success "No driver updates are currently available."
    exit 0
}

$displayUpdates = foreach ($driver in $driverUpdates) {
    [PSCustomObject]@{
        Driver = $driver.Title
        SizeMB = [Math]::Round($driver.MaxDownloadSize / 1MB, 2)
        EulaAccepted = [bool]$driver.EulaAccepted
    }
}

Write-WarningMessage "$($driverUpdates.Count) driver update(s) are available."
$displayUpdates | Format-Table -AutoSize

if (-not $Update) {
    Write-Success "Driver check complete. No drivers were changed."
    Write-Host "Run this script with -Update to install selected drivers." -ForegroundColor $script:ColorMuted
    exit 0
}

$failures = 0
$installed = 0
$rebootRequired = $false

foreach ($driver in $driverUpdates) {
    if (-not (Confirm-Action -Prompt "Install driver update '$($driver.Title)'?" -Yes:$Yes)) {
        continue
    }

    try {
        if (-not $driver.EulaAccepted) {
            $driver.AcceptEula()
        }

        $collection = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$collection.Add($driver)

        Write-Host "Downloading $($driver.Title)..." -ForegroundColor $script:ColorMuted
        $downloader = $driverState.Session.CreateUpdateDownloader()
        $downloader.Updates = $collection
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -notin @(2, 3)) {
            Write-ErrorMessage "Driver download failed with result code $($downloadResult.ResultCode)."
            $failures++
            continue
        }
        if ($downloadResult.ResultCode -eq 3) {
            Write-WarningMessage "Driver download completed with errors; installation will still be attempted."
        }

        Write-Host "Installing $($driver.Title)..." -ForegroundColor $script:ColorMuted
        $installer = $driverState.Session.CreateUpdateInstaller()
        $installer.Updates = $collection
        $installResult = $installer.Install()

        if ($installResult.ResultCode -eq 2) {
            Write-Success "Installed $($driver.Title)."
            $installed++
        }
        else {
            Write-ErrorMessage "Driver installation finished with result code $($installResult.ResultCode)."
            $failures++
        }

        if ($installResult.RebootRequired) {
            $rebootRequired = $true
        }
    }
    catch {
        Write-ErrorMessage "Driver update failed: $($_.Exception.Message)"
        $failures++
    }
}

Write-Host ""
Write-Host "Installed: $installed; Failed: $failures" -ForegroundColor $script:ColorMuted

if ($rebootRequired) {
    Write-WarningMessage "A system restart is required to finish installing drivers."
    if ($Restart -and (Confirm-Action -Prompt "Restart Windows now?" -Yes:$Yes)) {
        Restart-Computer
        exit 0
    }
    Write-Host "Restart Windows manually when convenient." -ForegroundColor $script:ColorMuted
}

if ($failures -gt 0) { exit 1 }
Write-Success "Driver update process complete."
