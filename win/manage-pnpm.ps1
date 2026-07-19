<#
.SYNOPSIS
    Checks, updates, installs, or repairs pnpm without mixing installation methods.
.DESCRIPTION
    The default mode is read-only. Use -Update for an existing installation or
    -Install for a missing installation. -InstallMethod is only used with -Install.
#>

[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Install,
    [switch]$Yes,
    [ValidateSet('Standalone', 'Npm', 'Corepack')]
    [string]$InstallMethod = 'Standalone'
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

if ($Update -and $Install) {
    Write-ErrorMessage "Choose either -Update or -Install, not both."
    exit 2
}
if ($Yes -and -not ($Update -or $Install)) {
    Write-ErrorMessage "-Yes requires -Update or -Install."
    exit 2
}

function Get-PnpmInstallationMethod {
    $path = Get-CommandPath pnpm
    if (-not $path) { return 'None' }

    $normalizedPath = [IO.Path]::GetFullPath($path)
    if ($env:APPDATA -and $normalizedPath.StartsWith([IO.Path]::Combine($env:APPDATA, 'npm'), [StringComparison]::OrdinalIgnoreCase)) {
        return 'Npm'
    }
    if ($env:PNPM_HOME -and $normalizedPath.StartsWith([IO.Path]::GetFullPath($env:PNPM_HOME), [StringComparison]::OrdinalIgnoreCase)) {
        return 'Standalone'
    }
    if ($env:LOCALAPPDATA -and $normalizedPath.StartsWith([IO.Path]::Combine($env:LOCALAPPDATA, 'pnpm'), [StringComparison]::OrdinalIgnoreCase)) {
        return 'Standalone'
    }

    if ([IO.Path]::GetExtension($path) -in @('.cmd', '.ps1')) {
        $shimContent = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
        if ($shimContent -match '(?i)corepack') {
            return 'Corepack'
        }
    }
    return 'Unknown'
}

function Invoke-StandalonePnpmInstaller {
    $installerPath = Join-Path ([IO.Path]::GetTempPath()) ("pnpm-install-{0}.ps1" -f [Guid]::NewGuid())
    try {
        Invoke-WebRequest -Uri "https://get.pnpm.io/install.ps1" -OutFile $installerPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $powerShellPath = (Get-Process -Id $PID).Path
        & $powerShellPath -NoProfile -ExecutionPolicy Bypass -File $installerPath
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-ErrorMessage "The standalone pnpm installer failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PnpmOperation {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][Version]$TargetVersion,
        [switch]$Repair
    )

    switch ($Method) {
        'Npm' {
            if (-not (Test-CommandAvailable npm)) {
                Write-ErrorMessage "This pnpm installation is managed by npm, but npm is unavailable."
                return $false
            }
            & npm install --global "pnpm@$TargetVersion"
            return ($LASTEXITCODE -eq 0)
        }
        'Corepack' {
            if (-not (Test-CommandAvailable corepack)) {
                Write-ErrorMessage "This pnpm installation is managed by Corepack, but Corepack is unavailable."
                return $false
            }
            & corepack install --global "pnpm@$TargetVersion"
            return ($LASTEXITCODE -eq 0)
        }
        'Standalone' {
            if (-not $Repair -and (Test-CommandAvailable pnpm)) {
                $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("pnpm-self-update-{0}" -f [Guid]::NewGuid())
                New-Item -ItemType Directory -Path $temporaryDirectory -ErrorAction Stop | Out-Null
                try {
                    Push-Location $temporaryDirectory
                    & pnpm self-update "$TargetVersion"
                    return ($LASTEXITCODE -eq 0)
                }
                finally {
                    Pop-Location
                    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            return (Invoke-StandalonePnpmInstaller)
        }
        default {
            Write-ErrorMessage "The active pnpm installation method could not be identified safely."
            return $false
        }
    }
}

Write-Section "=== pnpm Manager ==="

$pnpmAvailable = Test-CommandAvailable pnpm
$currentVersion = $null
$pnpmWorks = $false
$method = if ($pnpmAvailable) { Get-PnpmInstallationMethod } else { 'None' }

if ($pnpmAvailable) {
    $currentText = (& pnpm --version 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $currentText) {
        try {
            $currentVersion = ConvertTo-VersionNumber $currentText
            $pnpmWorks = $true
        }
        catch {}
    }
}

try {
    $latestResponse = Get-RemoteJson -Uri "https://registry.npmjs.org/pnpm/latest"
    $latestVersion = ConvertTo-VersionNumber ([string]$latestResponse.version)
}
catch {
    Write-ErrorMessage "Could not retrieve the latest pnpm version: $($_.Exception.Message)"
    exit 1
}

Write-Host "Executable:          $(if ($pnpmAvailable) { Get-CommandPath pnpm } else { 'not found' })" -ForegroundColor $script:ColorMuted
Write-Host "Installation method: $method" -ForegroundColor $script:ColorMuted
Write-Host "Current version:     $(if ($currentVersion) { $currentVersion } else { 'unavailable' })" -ForegroundColor $script:ColorMuted
Write-Host "Latest version:      $latestVersion" -ForegroundColor $script:ColorMuted

if (-not $pnpmAvailable) {
    if (-not $Install) {
        Write-WarningMessage "pnpm is not installed. Use -Install and optionally -InstallMethod to install it explicitly."
        exit 1
    }
    $method = $InstallMethod
}
elseif (-not $pnpmWorks) {
    if (-not $Update) {
        Write-WarningMessage "pnpm is installed but not working. Use -Update to repair it with the detected method."
        exit 1
    }
}
elseif ($currentVersion -ge $latestVersion) {
    Write-Success "pnpm is already up to date."
    exit 0
}
elseif (-not $Update) {
    Write-WarningMessage "A newer pnpm version is available: $currentVersion -> $latestVersion"
    Write-Host "Run this script with -Update to install it." -ForegroundColor $script:ColorMuted
    exit 0
}

if ($method -eq 'Unknown' -or $method -eq 'None') {
    Write-ErrorMessage "The pnpm installation method could not be determined safely."
    exit 1
}

$action = if ($Install) { 'Install' } elseif ($pnpmWorks) { 'Update' } else { 'Repair' }
if (-not (Confirm-Action -Prompt "$action pnpm $latestVersion using $method?" -Yes:$Yes)) {
    Write-Success "No packages were changed."
    exit 0
}

$operationSucceeded = Invoke-PnpmOperation -Method $method -TargetVersion $latestVersion -Repair:(-not $pnpmWorks)
if (-not $operationSucceeded) {
    Write-ErrorMessage "$action failed. No alternative installation method was attempted."
    exit 1
}

$newText = if (Test-CommandAvailable pnpm) { (& pnpm --version 2>$null | Out-String).Trim() } else { $null }
if ($newText) {
    try {
        $newVersion = ConvertTo-VersionNumber $newText
        if ($newVersion -ge $latestVersion) {
            Write-Success "pnpm is ready. Active version: $newVersion"
            exit 0
        }
    }
    catch {}
}

Write-Success "$action completed. Open a new terminal and run 'pnpm --version' to verify the active version."
