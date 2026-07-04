<#
.SYNOPSIS
    Escanea todas las aplicaciones instaladas en la computadora
    (Registro, Microsoft Store, Winget, NPM y PNPM) y permite actualizarlas de forma interactiva.
.DESCRIPTION
    Este script une informacion de multiples fuentes para proveer un inventario completo de aplicaciones.
    Luego, busca actualizaciones disponibles y solicita confirmacion para actualizar cada una.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Colores premium para la terminal
$ColorPrimary = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"
$ColorMuted = "Gray"
$ColorInfo = "White"

function Show-Header {
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor $ColorPrimary
    Write-Host "        DETECTOR Y GESTOR DE ACTUALIZACIONES TOTAL" -ForegroundColor $ColorPrimary
    Write-Host "=========================================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Funciones de Deteccion ---

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

# --- Funciones de Actualizacion (Upgrades) ---

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

# --- Flujo Principal del Script ---

Show-Header

$IsAdmin = Test-IsAdmin
if (-not $IsAdmin) {
    Write-Host "[INFO] Ejecutando en modo de usuario normal." -ForegroundColor $ColorInfo
    Write-Host "       El script solicitara privilegios de Administrador de forma individual" -ForegroundColor $ColorInfo
    Write-Host "       solo cuando se instalen actualizaciones de sistema que lo requieran." -ForegroundColor $ColorInfo
    Write-Host ""
}

Write-Host "[+] Iniciando escaneo de aplicaciones del sistema... Por favor espera." -ForegroundColor $ColorPrimary
Write-Host ""

# Ejecutar detecciones de forma sincrona para evitar problemas de ambito con Start-Job
Write-Host "[-] Escaneando Registro de Windows (apps de escritorio)... " -NoNewline -ForegroundColor $ColorInfo
$registryApps = Get-RegistryApps
Write-Host "Hecho ($($registryApps.Count) detectadas)" -ForegroundColor $ColorSuccess

Write-Host "[-] Escaneando Microsoft Store (Appx)... " -NoNewline -ForegroundColor $ColorInfo
$storeApps = Get-StoreApps
Write-Host "Hecho ($($storeApps.Count) detectadas)" -ForegroundColor $ColorSuccess

Write-Host "[-] Escaneando Windows Package Manager (Winget)... " -NoNewline -ForegroundColor $ColorInfo
$wingetApps = Get-WingetApps
Write-Host "Hecho ($($wingetApps.Count) detectadas)" -ForegroundColor $ColorSuccess

$npmApps = @()
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    Write-Host "[-] Escaneando paquetes globales de NPM... " -NoNewline -ForegroundColor $ColorInfo
    $npmApps = Get-NpmPackages
    Write-Host "Hecho ($($npmApps.Count) detectadas)" -ForegroundColor $ColorSuccess
}

$pnpmApps = @()
$pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
if ($pnpmCmd) {
    Write-Host "[-] Escaneando paquetes globales de PNPM... " -NoNewline -ForegroundColor $ColorInfo
    $pnpmApps = Get-PnpmPackages
    Write-Host "Hecho ($($pnpmApps.Count) detectadas)" -ForegroundColor $ColorSuccess
}

# Deduplicar y unificar
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
Write-Host " RESUMEN: Se detectaron $($unifiedApps.Count) aplicaciones en total." -ForegroundColor $ColorSuccess
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

# Buscar Actualizaciones
Write-Host "[+] Buscando actualizaciones disponibles..." -ForegroundColor $ColorPrimary
Write-Host ""

Write-Host "[-] Buscando actualizaciones en Winget y MS Store... " -NoNewline -ForegroundColor $ColorInfo
$wingetUpgrades = Get-WingetUpgrades
Write-Host "Hecho ($($wingetUpgrades.Count) encontradas)" -ForegroundColor $ColorSuccess

$npmUpgrades = @()
if ($npmCmd) {
    Write-Host "[-] Buscando actualizaciones en paquetes de NPM... " -NoNewline -ForegroundColor $ColorInfo
    $npmUpgrades = Get-NpmUpgrades
    Write-Host "Hecho ($($npmUpgrades.Count) encontradas)" -ForegroundColor $ColorSuccess
}

$allUpgrades = @()
$allUpgrades += $wingetUpgrades
$allUpgrades += $npmUpgrades

if ($allUpgrades.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] ¡Felicidades! Todas las aplicaciones estan al dia. No hay actualizaciones disponibles." -ForegroundColor $ColorSuccess
    Write-Host ""
    
    $viewAll = Read-Host "¿Deseas ver la lista completa de todas las aplicaciones detectadas? (S/N)"
    if ($viewAll.Trim().ToUpper() -eq "S") {
        Write-Host ""
        Write-Host ("{0,-60} {1,-20} {2}" -f "Nombre de la Aplicacion", "Version", "Origen") -ForegroundColor $ColorPrimary
        Write-Host ("{0,-60} {1,-20} {2}" -f "----------------------", "-------", "------") -ForegroundColor $ColorMuted
        foreach ($app in $unifiedApps.Values | Sort-Object Name) {
            $displayName = $app.Name
            if ($displayName.Length -gt 57) { $displayName = $displayName.Substring(0, 54) + "..." }
            Write-Host ("{0,-60} {1,-20} " -f $displayName, $app.Version) -NoNewline
            Write-Host $app.Source -ForegroundColor $ColorSuccess
        }
    }
    Write-Host ""
    Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor $ColorMuted
    try {
        [void][Console]::ReadKey($true)
    } catch {
        Read-Host
    }
    exit 0
}

Write-Host ""
Write-Host "Se encontraron $($allUpgrades.Count) actualizaciones disponibles:" -ForegroundColor $ColorWarning
Write-Host ""
Write-Host ("{0,-40} {1,-20} {2,-20} {3}" -f "Nombre de la Aplicacion", "Version Actual", "Version Nueva", "Origen") -ForegroundColor $ColorPrimary
Write-Host ("{0,-40} {1,-20} {2,-20} {3}" -f "----------------------", "--------------", "------------", "------") -ForegroundColor $ColorMuted

foreach ($upg in $allUpgrades) {
    $displayName = $upg.Name
    if ($displayName.Length -gt 37) { $displayName = $displayName.Substring(0, 34) + "..." }
    Write-Host ("{0,-40} {1,-20} {2,-20} " -f $displayName, $upg.Version, $upg.Available) -NoNewline
    Write-Host $upg.Source -ForegroundColor $ColorWarning
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host " INICIANDO FLUJO INTERACTIVO DE ACTUALIZACION" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

$autoUpdateAll = $false

foreach ($upg in $allUpgrades) {
    $action = "No"
    
    if (-not $autoUpdateAll) {
        while ($true) {
            Write-Host ""
            Write-Host ">>> ¿Deseas actualizar " -NoNewline
            Write-Host $upg.Name -NoNewline -ForegroundColor $ColorPrimary
            Write-Host " de " -NoNewline
            Write-Host "v$($upg.Version)" -NoNewline -ForegroundColor $ColorMuted
            Write-Host " a " -NoNewline
            Write-Host "v$($upg.Available)" -NoNewline -ForegroundColor $ColorSuccess
            Write-Host " ($($upg.Source))?"
            
            Write-Host "    [S] Si  [N] No  [A] Actualizar todos sin preguntar  [C] Cancelar y Salir: " -NoNewline -ForegroundColor $ColorInfo
            
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
            
            if ($key -eq "S" -or $key -eq "`r" -or $key -eq "`n") {
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
                Write-Host "[!] Opcion no valida. Presiona S, N, A o C." -ForegroundColor $ColorWarning
            }
        }
    } else {
        $action = "Yes"
    }
    
    if ($action -eq "Cancel") {
        Write-Host ""
        Write-Host "[!] Actualizaciones canceladas por el usuario. Saliendo..." -ForegroundColor $ColorWarning
        break
    }
    
    if ($action -eq "All") {
        $autoUpdateAll = $true
        $action = "Yes"
        Write-Host "[+] Activado modo de actualizacion masiva..." -ForegroundColor $ColorWarning
    }
    
    if ($action -eq "Yes") {
        Write-Host ""
        Write-Host "[+] Iniciando actualizacion de $($upg.Name)..." -ForegroundColor $ColorPrimary
        
        if ($upg.Type -eq "Winget") {
            try {
                if ($IsAdmin) {
                    & winget upgrade --id $upg.Id --accept-package-agreements --accept-source-agreements --include-unknown
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[SUCCESS] $($upg.Name) se actualizo correctamente." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[WARN] La actualizacion termino con el codigo de salida: $LASTEXITCODE. Revisa si la aplicacion se actualizo correctamente." -ForegroundColor $ColorWarning
                    }
                } else {
                    Write-Host "[-] Elevando privilegios para instalar la actualizacion..." -ForegroundColor $ColorMuted
                    $psPath = (Get-Process -Id $PID).Path
                    $cmd = "Write-Host 'Instalando $($upg.Name) como Administrador...'; & winget upgrade --id `"$($upg.Id)`" --accept-package-agreements --accept-source-agreements --include-unknown; `$exit = `$LASTEXITCODE; Start-Sleep -Seconds 3; exit `$exit"
                    $process = Start-Process $psPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs -Wait -PassThru
                    if ($process.ExitCode -eq 0) {
                        Write-Host "[SUCCESS] $($upg.Name) se actualizo correctamente." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[WARN] La actualizacion termino con el codigo de salida: $($process.ExitCode)." -ForegroundColor $ColorWarning
                    }
                }
            }
            catch {
                Write-Host "[ERROR] Error inesperado al actualizar mediante Winget: $_" -ForegroundColor $ColorError
            }
        }
        elseif ($upg.Type -eq "NPM") {
            try {
                if ($IsAdmin) {
                    & npm install -g "$($upg.Id)@latest"
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[SUCCESS] Paquete global NPM $($upg.Name) se actualizo correctamente." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[ERROR] Error al actualizar el paquete NPM $($upg.Name). Codigo: $LASTEXITCODE" -ForegroundColor $ColorError
                    }
                } else {
                    Write-Host "[-] Elevando privilegios para instalar el paquete NPM..." -ForegroundColor $ColorMuted
                    $psPath = (Get-Process -Id $PID).Path
                    $cmd = "Write-Host 'Instalando paquete NPM $($upg.Name) como Administrador...'; & npm install -g `"$($upg.Id)@latest`"; `$exit = `$LASTEXITCODE; Start-Sleep -Seconds 3; exit `$exit"
                    $process = Start-Process $psPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs -Wait -PassThru
                    if ($process.ExitCode -eq 0) {
                        Write-Host "[SUCCESS] Paquete global NPM $($upg.Name) se actualizo correctamente." -ForegroundColor $ColorSuccess
                    } else {
                        Write-Host "[ERROR] Error al actualizar el paquete NPM $($upg.Name). Codigo: $($process.ExitCode)" -ForegroundColor $ColorError
                    }
                }
            }
            catch {
                Write-Host "[ERROR] Error inesperado al actualizar mediante NPM: $_" -ForegroundColor $ColorError
            }
        }
    }
    else {
        Write-Host "[-] Saltando $($upg.Name)." -ForegroundColor $ColorMuted
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host "               PROCESO COMPLETADO" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor $ColorMuted
try {
    [void][Console]::ReadKey($true)
} catch {
    Read-Host
}
