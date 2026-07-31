<#
.SYNOPSIS
    Displays Node.js environment details and optionally updates the active major line.
.DESCRIPTION
    The default mode is read-only. Use -Update to request the latest patch release
    in the currently active Node.js major line.
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Update,
    [switch]$Yes
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

if ($Check -and $Update) {
    Write-ErrorMessage "-Check cannot be combined with -Update."
    exit 2
}
if ($Yes -and $Check) {
    Write-ErrorMessage "-Yes cannot be combined with -Check."
    exit 2
}

function Get-NodeEnvironment {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) { return $null }

    $version = (& node --version 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $version) { return $null }

    return [PSCustomObject]@{
        Version = ConvertTo-VersionNumber $version
        RawVersion = $version
        Path = Get-CommandPath node
        Architecture = (& node -p "process.arch" 2>$null | Out-String).Trim()
        Platform = (& node -p "process.platform" 2>$null | Out-String).Trim()
        V8 = (& node -p "process.versions.v8" 2>$null | Out-String).Trim()
        Libuv = (& node -p "process.versions.uv" 2>$null | Out-String).Trim()
        OpenSsl = (& node -p "process.versions.openssl" 2>$null | Out-String).Trim()
    }
}

function Get-WingetNodePackageId {
    if (-not (Test-CommandAvailable winget)) { return $null }

    foreach ($candidate in @('OpenJS.NodeJS.LTS', 'OpenJS.NodeJS')) {
        $output = (& winget list --id $candidate --exact --accept-source-agreements --disable-interactivity 2>$null | Out-String)
        if ($LASTEXITCODE -eq 0 -and $output -match [Regex]::Escape($candidate)) {
            return $candidate
        }
    }
    return $null
}

function Get-NodeManager {
    param([Parameter(Mandatory)][string]$NodePath)

    $fullPath = [IO.Path]::GetFullPath($NodePath)

    if ($env:PNPM_HOME -and $fullPath.StartsWith([IO.Path]::GetFullPath($env:PNPM_HOME), [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{ Name = 'pnpm'; PackageId = $null }
    }
    if ($fullPath -match '(?i)[\\/]pnpm[\\/]') {
        return [PSCustomObject]@{ Name = 'pnpm'; PackageId = $null }
    }
    if ($fullPath -match '(?i)[\\/]\.fnm[\\/]|fnm_multishells') {
        return [PSCustomObject]@{ Name = 'fnm'; PackageId = $null }
    }
    if ($env:NVM_SYMLINK -and $fullPath.StartsWith([IO.Path]::GetFullPath($env:NVM_SYMLINK), [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{ Name = 'nvm-windows'; PackageId = $null }
    }
    if ($env:VOLTA_HOME -and $fullPath.StartsWith([IO.Path]::GetFullPath($env:VOLTA_HOME), [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{ Name = 'Volta'; PackageId = $null }
    }

    $wingetId = Get-WingetNodePackageId
    if ($wingetId) {
        return [PSCustomObject]@{ Name = 'Winget'; PackageId = $wingetId }
    }
    return [PSCustomObject]@{ Name = 'Unknown'; PackageId = $null }
}

function Get-OptionalCommandVersion {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-CommandAvailable $Name)) { return 'not installed' }
    $value = (& $Name --version 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $value) { return 'not working' }
    return $value
}

Write-Section "=== Node.js Environment and Version ==="

try {
    $environment = Get-NodeEnvironment
}
catch {
    Write-ErrorMessage "Could not inspect Node.js: $($_.Exception.Message)"
    exit 1
}

if (-not $environment) {
    Write-ErrorMessage "Node.js is not installed or is not working."
    exit 1
}

$manager = Get-NodeManager -NodePath $environment.Path
$npmVersion = Get-OptionalCommandVersion npm
$pnpmVersion = Get-OptionalCommandVersion pnpm

Write-Host "Node.js version: $($environment.RawVersion) ($($environment.Platform) $($environment.Architecture))" -ForegroundColor $script:ColorSuccess
Write-Host "Executable:      $($environment.Path)" -ForegroundColor $script:ColorMuted
Write-Host "Manager:         $($manager.Name)" -ForegroundColor $script:ColorMuted
Write-Host "V8:              $($environment.V8)" -ForegroundColor $script:ColorMuted
Write-Host "libuv:           $($environment.Libuv)" -ForegroundColor $script:ColorMuted
Write-Host "OpenSSL:         $($environment.OpenSsl)" -ForegroundColor $script:ColorMuted
Write-Host "npm:             $npmVersion" -ForegroundColor $script:ColorMuted
Write-Host "pnpm:            $pnpmVersion" -ForegroundColor $script:ColorMuted

try {
    Write-Host ""
    Write-Host "Fetching release information from nodejs.org..." -ForegroundColor $script:ColorMuted
    $releases = @(Get-RemoteJson -Uri "https://nodejs.org/dist/index.json")
    if ($releases.Count -eq 0) { throw "The release list is empty." }

    $latestCurrent = $releases[0]
    $latestLts = $releases | Where-Object { $_.lts } | Select-Object -First 1
    $latestSameMajor = $releases |
        Where-Object { $_.version -match "^v$($environment.Version.Major)\." } |
        Select-Object -First 1

    if (-not $latestLts -or -not $latestSameMajor) {
        throw "Required release information is missing."
    }

    $targetVersion = ConvertTo-VersionNumber ([string]$latestSameMajor.version)
    $currentRelease = ConvertTo-VersionNumber ([string]$latestCurrent.version)
    $ltsRelease = ConvertTo-VersionNumber ([string]$latestLts.version)
}
catch {
    Write-ErrorMessage "Could not process Node.js release information: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "Latest LTS:          v$ltsRelease ($($latestLts.lts))" -ForegroundColor $script:ColorSuccess
Write-Host "Latest Current:      v$currentRelease" -ForegroundColor $script:ColorPrimary
Write-Host "Latest v$($environment.Version.Major) patch: v$targetVersion" -ForegroundColor $script:ColorMuted

if ($environment.Version -ge $targetVersion) {
    Write-Success "Node.js v$($environment.Version.Major) is already up to date."
    exit 0
}

if ($Check) {
    Write-WarningMessage "A newer patch is available: $($environment.Version) -> $targetVersion"
    exit 0
}

if ($manager.Name -eq 'Unknown') {
    Write-ErrorMessage "The active Node.js installation method could not be identified safely."
    exit 1
}

if (-not (Confirm-Action -Prompt "Install Node.js $targetVersion using $($manager.Name)?" -Yes:$Yes)) {
    Write-Success "No packages were changed."
    exit 0
}

$updateSucceeded = $false
switch ($manager.Name) {
    'pnpm' {
        if (-not (Test-CommandAvailable pnpm)) {
            Write-ErrorMessage "Node.js is managed by pnpm, but pnpm is unavailable."
            break
        }
        & pnpm runtime set node "$targetVersion" --global
        $updateSucceeded = $LASTEXITCODE -eq 0
    }
    'fnm' {
        if (-not (Test-CommandAvailable fnm)) {
            Write-ErrorMessage "Node.js is managed by fnm, but fnm is unavailable."
            break
        }
        & fnm install "$targetVersion"
        if ($LASTEXITCODE -eq 0) {
            & fnm default "$targetVersion"
            $updateSucceeded = $LASTEXITCODE -eq 0
        }
    }
    'nvm-windows' {
        if (-not (Test-CommandAvailable nvm)) {
            Write-ErrorMessage "Node.js is managed by nvm-windows, but nvm is unavailable."
            break
        }
        & nvm install "$targetVersion"
        if ($LASTEXITCODE -eq 0) {
            & nvm use "$targetVersion"
            $updateSucceeded = $LASTEXITCODE -eq 0
        }
    }
    'Volta' {
        if (-not (Test-CommandAvailable volta)) {
            Write-ErrorMessage "Node.js is managed by Volta, but Volta is unavailable."
            break
        }
        & volta install "node@$targetVersion"
        $updateSucceeded = $LASTEXITCODE -eq 0
    }
    'Winget' {
        & winget upgrade --id $manager.PackageId --exact --version "$targetVersion" --accept-package-agreements --accept-source-agreements --disable-interactivity
        $updateSucceeded = $LASTEXITCODE -eq 0
    }
}

if (-not $updateSucceeded) {
    Write-ErrorMessage "Node.js could not be updated through $($manager.Name)."
    exit 1
}

Write-Success "Node.js $targetVersion was installed successfully. Open a new terminal if the active version has not changed yet."
