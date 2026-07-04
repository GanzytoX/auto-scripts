<#
.SYNOPSIS
    Scans all installed applications on the computer
    (Registry, Microsoft Store, Winget, NPM, and PNPM) and allows interactive updates.
.DESCRIPTION
    This script merges information from multiple sources to provide a complete application inventory.
    It then checks for available updates and requests confirmation to update each one.
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
    Write-Host "        TOTAL UPDATE DETECTOR AND MANAGER" -ForegroundColor $ColorPrimary
    Write-Host "=========================================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Detection Functions ---

function Get-RegistryApps {
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    $apps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and $_.ParentKeyName -eq $null } |
        Select-Object @{N='Name'; E={$_.DisplayName}}, 
                      @{N='Version'; E={$_.DisplayVersion}}, 
                      @{N='Publisher'; E={$_.Publisher}}, 
                      @{N='Source'; E={'Registry'}}, 
                      @{N='Id'; E={$null}}
                      
    return $apps
}

function Get-StoreApps {
    $apps = Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object { -not $_.IsFramework -and $_.SignatureKind -eq "Store" -and $_.Name -notmatch "Microsoft.VCLibs|Microsoft.NET|Microsoft.Services|Windows" } |
        Select-Object @{N='Name'; E={$_.Name}}, 
                      @{N='Version'; E={$_.Version}}, 
                      @{N='Publisher'; E={$_.PublisherId}}, 
                      @{N='Source'; E={'MSStore'}}, 
                      @{N='Id'; E={$_.PackageFamilyName}}
                      
    return $apps
}

function Get-WingetApps {
    $originalBuffer = $Host.UI.RawUI.BufferSize
    try {
        $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(500, $Host.UI.RawUI.BufferSize.Height)
        $wingetOutput = winget list | Out-String
    }
    catch {
        $wingetOutput = winget list | Out-String
    }
    finally {
        if ($originalBuffer) {
            $Host.UI.RawUI.BufferSize = $originalBuffer
        }
    }
    
    $lines = $wingetOutput -split "`r?`n" | Where-Object { $_.Trim() }
    
    $headerIndex = -1
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i+1] -match "^--+$") {
            $headerIndex = $i
            break
        }
    }
    
    if ($headerIndex -eq -1) { return @() }
    
    $header = $lines[$headerIndex]
    $idxId = $header.IndexOf("Id")
    
    $idxVersion = $header.IndexOf("Version")
    if ($idxVersion -lt 0) { $idxVersion = $header.IndexOf("Versi") }
    
    $idxAvailable = $header.IndexOf("Available")
    if ($idxAvailable -lt 0) { $idxAvailable = $header.IndexOf("Dispon") }
    
    $idxSource = $header.IndexOf("Source")
    if ($idxSource -lt 0) { $idxSource = $header.IndexOf("Orig") }
    
    $cols = @()
    $cols += [PSCustomObject]@{ Name = "Id"; Index = $idxId }
    $cols += [PSCustomObject]@{ Name = "Version"; Index = $idxVersion }
    if ($idxAvailable -ge 0) {
        $cols += [PSCustomObject]@{ Name = "Available"; Index = $idxAvailable }
    }
    $cols += [PSCustomObject]@{ Name = "Source"; Index = $idxSource }
    
    $sortedCols = $cols | Sort-Object Index
    
    $results = @()
    for ($i = $headerIndex + 2; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "upgrades available|package\(s\) have version|actualizacion|paquete\(s\) tienen|tienen numeros") { continue }
        
        $lineLength = $line.Length
        
        # Calculate adjusted starts for this line
        $starts = @{}
        $starts["Name"] = 0
        
        for ($j = 0; $j -lt $sortedCols.Count; $j++) {
            $col = $sortedCols[$j]
            $start = $col.Index
            if ($start -gt 0 -and $lineLength -gt $start) {
                if ($line[$start] -ne ' ' -and $line[$start-1] -ne ' ') {
                    while ($start -gt 0 -and $line[$start - 1] -ne ' ') {
                        $start--
                    }
                }
            }
            $starts[$col.Name] = $start
        }
        
        $lineCols = @()
        $lineCols += [PSCustomObject]@{ Name = "Id"; Index = $starts["Id"] }
        $lineCols += [PSCustomObject]@{ Name = "Version"; Index = $starts["Version"] }
        if ($idxAvailable -ge 0) {
            $lineCols += [PSCustomObject]@{ Name = "Available"; Index = $starts["Available"] }
        }
        $lineCols += [PSCustomObject]@{ Name = "Source"; Index = $starts["Source"] }
        
        $sortedLineCols = $lineCols | Sort-Object Index
        
        $name = if ($lineLength -gt 0) { $line.Substring(0, [Math]::Min($sortedLineCols[0].Index, $lineLength)).Trim() } else { "" }
        
        $valId = ""
        $valVersion = ""
        $valAvailable = ""
        $valSource = ""
        
        for ($j = 0; $j -lt $sortedLineCols.Count; $j++) {
            $col = $sortedLineCols[$j]
            $start = $col.Index
            $end = if ($j -lt $sortedLineCols.Count - 1) { $sortedLineCols[$j+1].Index } else { $lineLength }
            
            $val = ""
            if ($lineLength -gt $start) {
                $length = $end - $start
                $val = $line.Substring($start, [Math]::Min($length, $lineLength - $start)).Trim()
            }
            
            switch ($col.Name) {
                "Id" { $valId = $val }
                "Version" { $valVersion = $val }
                "Available" { $valAvailable = $val }
                "Source" { $valSource = $val }
            }
        }
        
        $results += [PSCustomObject]@{
            Name      = $name
            Id        = $valId
            Version   = $valVersion
            Available = $valAvailable
            Source    = if ($valSource) { "Winget ($valSource)" } else { "Winget" }
        }
    }
    
    return $results
}

function Get-NpmPackages {
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) { return @() }
    
    $jsonStr = & npm list -g --depth=0 --json 2>$null | Out-String
    if ($jsonStr -and $jsonStr.Trim()) {
        $data = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($data -and $data.dependencies) {
            $results = @()
            foreach ($name in $data.dependencies.psobject.properties.Name) {
                $pkgInfo = $data.dependencies.$name
                $version = $pkgInfo.version
                if (-not $version -and $pkgInfo.resolved) { $version = "installed" }
                $results += [PSCustomObject]@{
                    Name      = $name
                    Id        = $name
                    Version   = $version
                    Publisher = "NPM Registry"
                    Source    = "NPM (Global)"
                }
            }
            return $results
        }
    }
    return @()
}

function Get-PnpmPackages {
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpmCmd) { return @() }
    
    $testOut = & pnpm list -g --depth 0 --json 2>$null | Out-String
    if ($testOut -and $testOut.Trim()) {
        $data = $testOut | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($data) {
            $results = @()
            foreach ($item in $data) {
                if ($item.dependencies) {
                    foreach ($name in $item.dependencies.psobject.properties.Name) {
                        $pkgInfo = $item.dependencies.$name
                        $results += [PSCustomObject]@{
                            Name      = $name
                            Id        = $name
                            Version   = $pkgInfo.version
                            Publisher = "PNPM Registry"
                            Source    = "PNPM (Global)"
                        }
                    }
                }
            }
            return $results
        }
    }
    return @()
}

# --- Upgrade Functions ---

function Get-WingetUpgrades {
    $originalBuffer = $Host.UI.RawUI.BufferSize
    try {
        $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(500, $Host.UI.RawUI.BufferSize.Height)
        $wingetOutput = winget upgrade --include-unknown | Out-String
    }
    catch {
        $wingetOutput = winget upgrade --include-unknown | Out-String
    }
    finally {
        if ($originalBuffer) {
            $Host.UI.RawUI.BufferSize = $originalBuffer
        }
    }
    
    $lines = $wingetOutput -split "`r?`n" | Where-Object { $_.Trim() }
    
    $headerIndex = -1
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i+1] -match "^--+$") {
            $headerIndex = $i
            break
        }
    }
    
    if ($headerIndex -eq -1) { return @() }
    
    $header = $lines[$headerIndex]
    $idxId = $header.IndexOf("Id")
    
    $idxVersion = $header.IndexOf("Version")
    if ($idxVersion -lt 0) { $idxVersion = $header.IndexOf("Versi") }
    
    $idxAvailable = $header.IndexOf("Available")
    if ($idxAvailable -lt 0) { $idxAvailable = $header.IndexOf("Dispon") }
    
    $idxSource = $header.IndexOf("Source")
    if ($idxSource -lt 0) { $idxSource = $header.IndexOf("Orig") }
    
    $cols = @()
    $cols += [PSCustomObject]@{ Name = "Id"; Index = $idxId }
    $cols += [PSCustomObject]@{ Name = "Version"; Index = $idxVersion }
    if ($idxAvailable -ge 0) {
        $cols += [PSCustomObject]@{ Name = "Available"; Index = $idxAvailable }
    }
    $cols += [PSCustomObject]@{ Name = "Source"; Index = $idxSource }
    
    $sortedCols = $cols | Sort-Object Index
    
    $results = @()
    for ($i = $headerIndex + 2; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "upgrades available|package\(s\) have version|actualizacion|paquete\(s\) tienen|tienen numeros") { continue }
        
        $lineLength = $line.Length
        
        # Calculate adjusted starts for this line
        $starts = @{}
        $starts["Name"] = 0
        
        for ($j = 0; $j -lt $sortedCols.Count; $j++) {
            $col = $sortedCols[$j]
            $start = $col.Index
            if ($start -gt 0 -and $lineLength -gt $start) {
                if ($line[$start] -ne ' ' -and $line[$start-1] -ne ' ') {
                    while ($start -gt 0 -and $line[$start - 1] -ne ' ') {
                        $start--
                    }
                }
            }
            $starts[$col.Name] = $start
        }
        
        $lineCols = @()
        $lineCols += [PSCustomObject]@{ Name = "Id"; Index = $starts["Id"] }
        $lineCols += [PSCustomObject]@{ Name = "Version"; Index = $starts["Version"] }
        if ($idxAvailable -ge 0) {
            $lineCols += [PSCustomObject]@{ Name = "Available"; Index = $starts["Available"] }
        }
        $lineCols += [PSCustomObject]@{ Name = "Source"; Index = $starts["Source"] }
        
        $sortedLineCols = $lineCols | Sort-Object Index
        
        $name = if ($lineLength -gt 0) { $line.Substring(0, [Math]::Min($sortedLineCols[0].Index, $lineLength)).Trim() } else { "" }
        
        $valId = ""
        $valVersion = ""
        $valAvailable = ""
        $valSource = ""
        
        for ($j = 0; $j -lt $sortedLineCols.Count; $j++) {
            $col = $sortedLineCols[$j]
            $start = $col.Index
            $end = if ($j -lt $sortedLineCols.Count - 1) { $sortedLineCols[$j+1].Index } else { $lineLength }
            
            $val = ""
            if ($lineLength -gt $start) {
                $length = $end - $start
                $val = $line.Substring($start, [Math]::Min($length, $lineLength - $start)).Trim()
            }
            
            switch ($col.Name) {
                "Id" { $valId = $val }
                "Version" { $valVersion = $val }
                "Available" { $valAvailable = $val }
                "Source" { $valSource = $val }
            }
        }
        
        $results += [PSCustomObject]@{
            Name      = $name
            Id        = $valId
            Version   = $valVersion
            Available = $valAvailable
            Source    = if ($valSource) { "Winget ($valSource)" } else { "Winget" }
            Type      = "Winget"
        }
    }
    
    return $results
}

function Get-NpmUpgrades {
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) { return @() }
    
    $jsonStr = & npm outdated -g --json 2>$null | Out-String
    if ($jsonStr -and $jsonStr.Trim()) {
        $data = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($data) {
            $results = @()
            foreach ($prop in $data.psobject.properties) {
                $pkgName = $prop.Name
                $pkgInfo = $prop.Value
                if ($pkgInfo.current -ne $pkgInfo.latest) {
                    $results += [PSCustomObject]@{
                        Name      = $pkgName
                        Id        = $pkgName
                        Version   = $pkgInfo.current
                        Available = $pkgInfo.latest
                        Source    = "NPM (Global)"
                        Type      = "NPM"
                    }
                }
            }
            return $results
        }
    }
    return @()
}

# --- Main Script Flow ---

Show-Header

$IsAdmin = Test-IsAdmin
if (-not $IsAdmin) {
    Write-Host "[INFO] Running in normal user mode." -ForegroundColor $ColorInfo
    Write-Host "       The script will request Administrator privileges individually" -ForegroundColor $ColorInfo
    Write-Host "       only when system updates require them." -ForegroundColor $ColorInfo
    Write-Host ""
}

Write-Host "[+] Starting system applications scan... Please wait." -ForegroundColor $ColorPrimary
Write-Host ""

# Run scans synchronously to avoid scope issues with Start-Job
Write-Host "[-] Scanning Windows Registry (desktop apps)... " -NoNewline -ForegroundColor $ColorInfo
$registryApps = Get-RegistryApps
Write-Host "Done ($($registryApps.Count) detected)" -ForegroundColor $ColorSuccess

Write-Host "[-] Scanning Microsoft Store (Appx)... " -NoNewline -ForegroundColor $ColorInfo
$storeApps = Get-StoreApps
Write-Host "Done ($($storeApps.Count) detected)" -ForegroundColor $ColorSuccess

Write-Host "[-] Scanning Windows Package Manager (Winget)... " -NoNewline -ForegroundColor $ColorInfo
$wingetApps = Get-WingetApps
Write-Host "Done ($($wingetApps.Count) detected)" -ForegroundColor $ColorSuccess

$npmApps = @()
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    Write-Host "[-] Scanning NPM global packages... " -NoNewline -ForegroundColor $ColorInfo
    $npmApps = Get-NpmPackages
    Write-Host "Done ($($npmApps.Count) detected)" -ForegroundColor $ColorSuccess
}

$pnpmApps = @()
$pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
if ($pnpmCmd) {
    Write-Host "[-] Scanning PNPM global packages... " -NoNewline -ForegroundColor $ColorInfo
    $pnpmApps = Get-PnpmPackages
    Write-Host "Done ($($pnpmApps.Count) detected)" -ForegroundColor $ColorSuccess
}

# Deduplicate and unify
$unifiedApps = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($app in $wingetApps) {
    $key = $app.Name.Trim()
    if ($key -and -not $unifiedApps.ContainsKey($key)) {
        $unifiedApps[$key] = $app
    }
}

foreach ($app in $registryApps) {
    $key = $app.Name.Trim()
    if ($key -and -not $unifiedApps.ContainsKey($key)) {
        $unifiedApps[$key] = $app
    }
}

foreach ($app in $storeApps) {
    $key = $app.Name.Trim()
    $found = $false
    foreach ($val in $unifiedApps.Values) {
        if ($val.Id -eq $app.Id) {
            $found = $true
            break
        }
    }
    if (-not $found -and -not $unifiedApps.ContainsKey($key)) {
        $unifiedApps[$key] = $app
    }
}

foreach ($app in $npmApps) {
    $key = $app.Name.Trim()
    if ($key -and -not $unifiedApps.ContainsKey($key)) {
        $unifiedApps[$key] = $app
    }
}

foreach ($app in $pnpmApps) {
    $key = $app.Name.Trim()
    if ($key -and -not $unifiedApps.ContainsKey($key)) {
        $unifiedApps[$key] = $app
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host " SUMMARY: $($unifiedApps.Count) applications detected in total." -ForegroundColor $ColorSuccess
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

# Check for Updates
Write-Host "[+] Checking for available updates..." -ForegroundColor $ColorPrimary
Write-Host ""

Write-Host "[-] Checking for updates in Winget and MS Store... " -NoNewline -ForegroundColor $ColorInfo
$wingetUpgrades = Get-WingetUpgrades
Write-Host "Done ($($wingetUpgrades.Count) found)" -ForegroundColor $ColorSuccess

$npmUpgrades = @()
if ($npmCmd) {
    Write-Host "[-] Checking for updates in NPM packages... " -NoNewline -ForegroundColor $ColorInfo
    $npmUpgrades = Get-NpmUpgrades
    Write-Host "Done ($($npmUpgrades.Count) found)" -ForegroundColor $ColorSuccess
}

$allUpgrades = @()
$allUpgrades += $wingetUpgrades
$allUpgrades += $npmUpgrades

if ($allUpgrades.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] Congratulations! All applications are up to date. No updates available." -ForegroundColor $ColorSuccess
    Write-Host ""
    
    $viewAll = Read-Host "Do you want to see the full list of detected applications? (Y/N)"
    if ($viewAll.Trim().ToUpper() -eq "Y") {
        Write-Host ""
        Write-Host ("{0,-60} {1,-20} {2}" -f "Application Name", "Version", "Source") -ForegroundColor $ColorPrimary
        Write-Host ("{0,-60} {1,-20} {2}" -f "----------------", "-------", "------") -ForegroundColor $ColorMuted
        foreach ($app in $unifiedApps.Values | Sort-Object Name) {
            $displayName = $app.Name
            if ($displayName.Length -gt 57) { $displayName = $displayName.Substring(0, 54) + "..." }
            Write-Host ("{0,-60} {1,-20} " -f $displayName, $app.Version) -NoNewline
            Write-Host $app.Source -ForegroundColor $ColorSuccess
        }
    }
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor $ColorMuted
    try {
        [void][Console]::ReadKey($true)
    } catch {
        Read-Host
    }
    exit 0
}

Write-Host ""
Write-Host "Found $($allUpgrades.Count) available updates:" -ForegroundColor $ColorWarning
Write-Host ""
Write-Host ("{0,-40} {1,-20} {2,-20} {3}" -f "Application Name", "Current Version", "New Version", "Source") -ForegroundColor $ColorPrimary
Write-Host ("{0,-40} {1,-20} {2,-20} {3}" -f "----------------", "---------------", "-----------", "------") -ForegroundColor $ColorMuted

foreach ($upg in $allUpgrades) {
    $displayName = $upg.Name
    if ($displayName.Length -gt 37) { $displayName = $displayName.Substring(0, 34) + "..." }
    Write-Host ("{0,-40} {1,-20} {2,-20} " -f $displayName, $upg.Version, $upg.Available) -NoNewline
    Write-Host $upg.Source -ForegroundColor $ColorWarning
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host "        STARTING INTERACTIVE UPDATE FLOW" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

$autoUpdateAll = $false

foreach ($upg in $allUpgrades) {
    $action = "No"
    
    if (-not $autoUpdateAll) {
        while ($true) {
            Write-Host ""
            Write-Host ">>> Do you want to update " -NoNewline
            Write-Host $upg.Name -NoNewline -ForegroundColor $ColorPrimary
            Write-Host " from " -NoNewline
            Write-Host "v$($upg.Version)" -NoNewline -ForegroundColor $ColorMuted
            Write-Host " to " -NoNewline
            Write-Host "v$($upg.Available)" -NoNewline -ForegroundColor $ColorSuccess
            Write-Host " ($($upg.Source))?"
            
            Write-Host "    [Y] Yes  [N] No  [A] Update all without asking  [C] Cancel and Exit: " -NoNewline -ForegroundColor $ColorInfo
            
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
        Write-Host "[!] Updates cancelled by the user. Exiting..." -ForegroundColor $ColorWarning
        break
    }
    
    if ($action -eq "All") {
        $autoUpdateAll = $true
        $action = "Yes"
        Write-Host "[+] Bulk update mode activated..." -ForegroundColor $ColorWarning
    }
    
    if ($action -eq "Yes") {
        Write-Host ""
        Write-Host "[+] Starting update for $($upg.Name)..." -ForegroundColor $ColorPrimary
        
        if ($upg.Type -eq "Winget") {
            try {
                if ($IsAdmin) {
                    & winget upgrade --id $upg.Id --accept-package-agreements --accept-source-agreements --include-unknown
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[SUCCESS] $($upg.Name) updated successfully." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[WARN] Update finished with exit code: $LASTEXITCODE. Please check if the application updated correctly." -ForegroundColor $ColorWarning
                    }
                } else {
                    Write-Host "[-] Elevating privileges to install the update..." -ForegroundColor $ColorMuted
                    $psPath = (Get-Process -Id $PID).Path
                    $cmd = "Write-Host 'Installing $($upg.Name) as Administrator...'; & winget upgrade --id `"$($upg.Id)`" --accept-package-agreements --accept-source-agreements --include-unknown; `$exit = `$LASTEXITCODE; Start-Sleep -Seconds 3; exit `$exit"
                    $process = Start-Process $psPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs -Wait -PassThru
                    if ($process.ExitCode -eq 0) {
                        Write-Host "[SUCCESS] $($upg.Name) updated successfully." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[WARN] Update finished with exit code: $($process.ExitCode)." -ForegroundColor $ColorWarning
                    }
                }
            }
            catch {
                Write-Host "[ERROR] Unexpected error while updating via Winget: $_" -ForegroundColor $ColorError
            }
        }
        elseif ($upg.Type -eq "NPM") {
            try {
                if ($IsAdmin) {
                    & npm install -g "$($upg.Id)@latest"
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[SUCCESS] Global NPM package $($upg.Name) updated successfully." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[ERROR] Error updating NPM package $($upg.Name). Code: $LASTEXITCODE" -ForegroundColor $ColorError
                    }
                } else {
                    Write-Host "[-] Elevating privileges to install the NPM package..." -ForegroundColor $ColorMuted
                    $psPath = (Get-Process -Id $PID).Path
                    $cmd = "Write-Host 'Installing NPM package $($upg.Name) as Administrator...'; & npm install -g `"$($upg.Id)@latest`"; `$exit = `$LASTEXITCODE; Start-Sleep -Seconds 3; exit `$exit"
                    $process = Start-Process $psPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs -Wait -PassThru
                    if ($process.ExitCode -eq 0) {
                        Write-Host "[SUCCESS] Global NPM package $($upg.Name) updated successfully." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[ERROR] Error updating NPM package $($upg.Name). Code: $($process.ExitCode)" -ForegroundColor $ColorError
                    }
                }
            }
            catch {
                Write-Host "[ERROR] Unexpected error while updating via NPM: $_" -ForegroundColor $ColorError
            }
        }
    }
    else {
        Write-Host "[-] Skipping $($upg.Name)." -ForegroundColor $ColorMuted
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host "                   PROCESS COMPLETED" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

Write-Host "Press any key to exit..." -ForegroundColor $ColorMuted
try {
    [void][Console]::ReadKey($true)
} catch {
    Read-Host
}
