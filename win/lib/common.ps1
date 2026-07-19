Set-StrictMode -Version 2.0

$script:ColorPrimary = "Cyan"
$script:ColorSuccess = "Green"
$script:ColorWarning = "Yellow"
$script:ColorError = "Red"
$script:ColorMuted = "DarkGray"

function Initialize-ScriptEnvironment {
    [CmdletBinding()]
    param([switch]$Clear)

    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    if ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) {
        # TLS 1.2 is already enabled.
    }
    else {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    if ($Clear -and $Host.Name -eq "ConsoleHost" -and -not [Console]::IsOutputRedirected) {
        Clear-Host
    }
}

function Write-Section {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor $script:ColorPrimary
}

function Write-Success {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor $script:ColorSuccess
}

function Write-WarningMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning $Message
}

function Write-ErrorMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor $script:ColorError
}

function Test-CommandAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$Yes
    )

    if ($Yes) {
        return $true
    }

    if ([Console]::IsInputRedirected) {
        return $false
    }

    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match '^(?i:y|yes)$'
}

function ConvertTo-VersionNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)

    $normalized = $Version.Trim() -replace '^v', ''
    if ($normalized -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid semantic version: $Version"
    }
    return [Version]$normalized
}

function Get-RemoteJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [int]$TimeoutSec = 20
    )

    return (Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop)
}

function Get-CommandPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        return $null
    }

    $pathProperty = $command.PSObject.Properties['Path']
    if ($pathProperty -and $pathProperty.Value) {
        return [string]$pathProperty.Value
    }

    $sourceProperty = $command.PSObject.Properties['Source']
    if ($sourceProperty) {
        return [string]$sourceProperty.Value
    }
    return $null
}
