<#
.SYNOPSIS
    Lists globally installed npm and pnpm packages.
.DESCRIPTION
    Displays package names, versions, manager versions, and global installation paths.
    This script is read-only.
#>

[CmdletBinding()]
param(
    [switch]$Npm,
    [switch]$Pnpm
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

$checkNpm = $Npm -or (-not $Npm -and -not $Pnpm)
$checkPnpm = $Pnpm -or (-not $Npm -and -not $Pnpm)
$successfulManagers = 0

function Get-GlobalPackages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('npm', 'pnpm')][string]$Manager)

    $displayName = $Manager.ToUpperInvariant()
    Write-Section "--- $displayName global packages ---"

    if (-not (Test-CommandAvailable $Manager)) {
        Write-WarningMessage "$displayName is not installed or is not available in PATH."
        Write-Host ""
        return $false
    }

    $managerVersion = (& $Manager --version 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $managerVersion) {
        Write-ErrorMessage "$displayName is present but its executable is not working."
        Write-Host "Executable: $(Get-CommandPath $Manager)" -ForegroundColor $script:ColorMuted
        Write-Host ""
        return $false
    }

    $globalPath = (& $Manager root --global 2>$null | Out-String).Trim()
    Write-Host "Version:          $managerVersion" -ForegroundColor $script:ColorMuted
    if ($globalPath) {
        Write-Host "Global directory: $globalPath" -ForegroundColor $script:ColorMuted
    }

    $errorFile = [IO.Path]::GetTempFileName()
    try {
        $jsonText = (& $Manager list --global --depth=0 --json 2>$errorFile | Out-String).Trim()
        $queryExitCode = $LASTEXITCODE
        $queryError = (Get-Content -LiteralPath $errorFile -Raw -ErrorAction SilentlyContinue | Out-String).Trim()

        if (-not $jsonText) {
            Write-ErrorMessage "$displayName did not return package information."
            if ($queryError) { Write-Host $queryError -ForegroundColor $script:ColorError }
            return $false
        }

        try {
            $payload = $jsonText | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-ErrorMessage "$displayName returned invalid JSON: $($_.Exception.Message)"
            if ($queryError) { Write-Host $queryError -ForegroundColor $script:ColorError }
            return $false
        }

        if ($queryExitCode -ne 0 -and $queryError) {
            Write-WarningMessage "$displayName completed with a warning: $queryError"
        }

        $packages = [System.Collections.Generic.List[object]]::new()
        foreach ($root in @($payload)) {
            $dependenciesProperty = $root.PSObject.Properties['dependencies']
            if (-not $dependenciesProperty -or -not $dependenciesProperty.Value) { continue }
            foreach ($property in $dependenciesProperty.Value.PSObject.Properties) {
                $versionProperty = $property.Value.PSObject.Properties['version']
                $version = if ($versionProperty -and $versionProperty.Value) { $versionProperty.Value } else { "unknown" }
                $packages.Add([PSCustomObject]@{
                    Package = $property.Name
                    Version = $version
                })
            }
        }

        if ($packages.Count -eq 0) {
            Write-WarningMessage "No global $displayName packages were found."
        }
        else {
            $packages | Sort-Object Package | Format-Table -AutoSize | Out-Host
            Write-Success "Total $displayName packages: $($packages.Count)"
        }

        Write-Host ""
        return $true
    }
    finally {
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Section "=== Global Node.js Packages ==="
Write-Host ""

if ($checkNpm -and (Get-GlobalPackages -Manager npm)) { $successfulManagers++ }
if ($checkPnpm -and (Get-GlobalPackages -Manager pnpm)) { $successfulManagers++ }

if ($successfulManagers -eq 0) {
    Write-ErrorMessage "No package manager could be queried successfully."
    exit 1
}

Write-Success "Global package inventory complete."
