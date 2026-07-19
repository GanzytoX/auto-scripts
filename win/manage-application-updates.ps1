<#
.SYNOPSIS
    Checks and optionally installs Windows application updates.
.DESCRIPTION
    Uses Winget for desktop and Microsoft Store applications and npm for global
    Node.js packages. The default mode is read-only.
#>

[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Yes,
    [switch]$Inventory,
    [switch]$IncludeUnknown
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

if ($Yes -and -not $Update) {
    Write-ErrorMessage "-Yes can only be used together with -Update."
    exit 2
}

function Get-NpmGlobalUpdates {
    if (-not (Test-CommandAvailable npm)) { return @() }

    $errorFile = [IO.Path]::GetTempFileName()
    try {
        $jsonText = (& npm outdated --global --json 2>$errorFile | Out-String).Trim()
        $nativeExitCode = $LASTEXITCODE
        $errorText = (Get-Content -LiteralPath $errorFile -Raw -ErrorAction SilentlyContinue | Out-String).Trim()

        # npm outdated returns a non-zero code when updates are found.
        if (-not $jsonText) {
            if ($nativeExitCode -ne 0 -and $errorText) {
                Write-WarningMessage "npm could not check global updates: $errorText"
            }
            return @()
        }

        try {
            $payload = $jsonText | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-WarningMessage "npm returned invalid update data: $($_.Exception.Message)"
            return @()
        }

        $updates = [System.Collections.Generic.List[object]]::new()
        foreach ($property in $payload.PSObject.Properties) {
            $metadata = $property.Value
            $currentProperty = $metadata.PSObject.Properties['current']
            $latestProperty = $metadata.PSObject.Properties['latest']
            if (-not $currentProperty -or -not $latestProperty) { continue }
            if (-not $currentProperty.Value -or -not $latestProperty.Value) { continue }
            if ([string]$currentProperty.Value -eq [string]$latestProperty.Value) { continue }

            $updates.Add([PSCustomObject]@{
                Name = $property.Name
                Current = [string]$currentProperty.Value
                Latest = [string]$latestProperty.Value
            })
        }
        return @($updates)
    }
    finally {
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    }
}

function Show-WingetInventory {
    if (-not (Test-CommandAvailable winget)) {
        Write-WarningMessage "Winget is not installed or is not available in PATH."
        return
    }

    Write-Section "--- Installed applications reported by Winget ---"
    & winget list --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-WarningMessage "Winget inventory exited with code $LASTEXITCODE."
    }
    Write-Host ""
}

function Show-WingetUpdates {
    if (-not (Test-CommandAvailable winget)) {
        Write-WarningMessage "Winget is unavailable; desktop and Store updates cannot be checked."
        return $false
    }

    $arguments = @('list', '--upgrade-available', '--accept-source-agreements', '--disable-interactivity')
    if ($IncludeUnknown) { $arguments += '--include-unknown' }

    Write-Section "--- Winget and Microsoft Store updates ---"
    & winget @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-WarningMessage "Winget update discovery exited with code $LASTEXITCODE. The output above may simply indicate that no upgrades are available."
    }
    Write-Host ""
    return $true
}

Write-Section "=== Windows Application Updates ==="
Write-Host ""

if ($Inventory) {
    Show-WingetInventory
    $globalPackageScript = Join-Path $PSScriptRoot 'list-global-node-packages.ps1'
    if (Test-Path -LiteralPath $globalPackageScript) {
        & $globalPackageScript
        Write-Host ""
    }
}

$wingetAvailable = Show-WingetUpdates

Write-Section "--- Global npm updates ---"
$npmUpdates = @(Get-NpmGlobalUpdates)
if ($npmUpdates.Count -eq 0) {
    if (Test-CommandAvailable npm) {
        Write-Success "No global npm updates were found."
    }
    else {
        Write-WarningMessage "npm is not installed or is not available in PATH."
    }
}
else {
    $npmUpdates | Format-Table Name, Current, Latest -AutoSize
    Write-WarningMessage "$($npmUpdates.Count) global npm update(s) are available."
}

if (-not $Update) {
    Write-Host ""
    Write-Success "Update check complete. No applications were changed."
    Write-Host "Run this script with -Update to install available updates." -ForegroundColor $script:ColorMuted
    exit 0
}

$failures = 0
if ($wingetAvailable -and (Confirm-Action -Prompt "Install all available Winget and Store updates?" -Yes:$Yes)) {
    $arguments = @('upgrade', '--all', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($IncludeUnknown) { $arguments += '--include-unknown' }

    & winget @arguments
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Winget updates completed successfully."
    }
    else {
        Write-ErrorMessage "Winget update exited with code $LASTEXITCODE."
        $failures++
    }
}

foreach ($package in $npmUpdates) {
    if (-not (Confirm-Action -Prompt "Update global npm package $($package.Name) from $($package.Current) to $($package.Latest)?" -Yes:$Yes)) {
        continue
    }

    & npm install --global "$($package.Name)@$($package.Latest)"
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Updated npm package $($package.Name)."
    }
    else {
        Write-ErrorMessage "npm failed to update $($package.Name) with code $LASTEXITCODE."
        $failures++
    }
}

if ($failures -gt 0) {
    Write-ErrorMessage "$failures update operation(s) failed."
    exit 1
}

Write-Success "Application update process complete."
