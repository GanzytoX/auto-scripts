<#
.SYNOPSIS
    Checks or updates the active npm installation.
.DESCRIPTION
    The default mode is read-only. Use -Update to request an update and -Yes for
    explicit non-interactive confirmation.
#>

[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Yes
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

if ($Yes -and -not $Update) {
    Write-ErrorMessage "-Yes can only be used together with -Update."
    exit 2
}

Write-Section "=== npm Version Manager ==="

if (-not (Test-CommandAvailable npm)) {
    Write-ErrorMessage "npm is not installed or is not available in PATH."
    exit 1
}

$currentText = (& npm --version 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $currentText) {
    Write-ErrorMessage "The npm executable exists but could not report its version."
    exit 1
}

try {
    $currentVersion = ConvertTo-VersionNumber $currentText
    $latestResponse = Get-RemoteJson -Uri "https://registry.npmjs.org/npm/latest"
    $latestVersion = ConvertTo-VersionNumber ([string]$latestResponse.version)
}
catch {
    Write-ErrorMessage "Could not determine npm versions: $($_.Exception.Message)"
    exit 1
}

Write-Host "Executable:      $(Get-CommandPath npm)" -ForegroundColor $script:ColorMuted
Write-Host "Current version: $currentVersion" -ForegroundColor $script:ColorMuted
Write-Host "Latest version:  $latestVersion" -ForegroundColor $script:ColorMuted

if ($currentVersion -ge $latestVersion) {
    Write-Success "npm is already up to date."
    exit 0
}

Write-WarningMessage "A newer npm version is available: $currentVersion -> $latestVersion"
if (-not $Update) {
    Write-Host "Run this script with -Update to install it." -ForegroundColor $script:ColorMuted
    exit 0
}

if (-not (Confirm-Action -Prompt "Update npm to $latestVersion?" -Yes:$Yes)) {
    Write-Success "No packages were changed."
    exit 0
}

& npm install --global "npm@$latestVersion"
if ($LASTEXITCODE -ne 0) {
    Write-ErrorMessage "npm exited with code $LASTEXITCODE while updating itself."
    exit 1
}

$newText = (& npm --version 2>$null | Out-String).Trim()
try {
    $newVersion = ConvertTo-VersionNumber $newText
}
catch {
    Write-ErrorMessage "npm completed the update but the active version could not be verified."
    exit 1
}

if ($newVersion -lt $latestVersion) {
    Write-ErrorMessage "npm is still older than expected after the update: $newVersion"
    exit 1
}

Write-Success "npm was updated successfully to $newVersion."
