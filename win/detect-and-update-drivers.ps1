<#
.SYNOPSIS
    Escanea todos los dispositivos de hardware de la computadora
    y busca/instala actualizaciones de controladores (drivers) desde Windows Update.
.DESCRIPTION
    Este script consulta los dispositivos conectados mediante PnpDevice, busca actualizaciones
    de controladores usando la API nativa de Windows Update, y permite instalarlas de forma interactiva.
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
    Write-Host "         DETECTOR Y GESTOR DE DRIVERS TOTAL" -ForegroundColor $ColorPrimary
    Write-Host "=========================================================" -ForegroundColor $ColorPrimary
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Flujo Principal del Script ---

Show-Header

# 1. Verificar Elevacion de Privilegios
$IsAdmin = Test-IsAdmin
if (-not $IsAdmin) {
    Write-Host "[ADVERTENCIA] No estas ejecutando este script como Administrador." -ForegroundColor $ColorWarning
    Write-Host "              La instalacion de controladores requiere privilegios elevados." -ForegroundColor $ColorWarning
    Write-Host ""
    Write-Host "Deseas reiniciar este script como Administrador automaticamente? [S] Si / [N] No: " -NoNewline -ForegroundColor $ColorInfo
    
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
        Write-Host ""
        Write-Host "[+] Reiniciando como Administrador..." -ForegroundColor $ColorSuccess
        try {
            $psPath = (Get-Process -Id $PID).Path
            Start-Process $psPath -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
            exit
        }
        catch {
            Write-Host "[ERROR] No se pudo elevar privilegios: $_" -ForegroundColor $ColorError
            Write-Host "Continuando en modo no administrador..." -ForegroundColor $ColorMuted
            Write-Host ""
        }
    } else {
        Write-Host ""
        Write-Host "Continuando en modo no administrador..." -ForegroundColor $ColorMuted
        Write-Host ""
    }
}

# 2. Escanear Hardware
Write-Host "[+] Iniciando escaneo de hardware de tu laptop... Por favor espera." -ForegroundColor $ColorPrimary
Write-Host ""

Write-Host "[-] Detectando dispositivos conectados... " -NoNewline -ForegroundColor $ColorInfo
$pnpDevices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
Write-Host "Hecho ($($pnpDevices.Count) dispositivos detectados)" -ForegroundColor $ColorSuccess

# Clasificacion por clase
$grouped = $pnpDevices | Group-Object Class -NoElement | Sort-Object Count -Descending
Write-Host ""
Write-Host "Resumen de hardware por categoria:" -ForegroundColor $ColorMuted
foreach ($grp in $grouped) {
    if ($grp.Name) {
        Write-Host "    -> $($grp.Name): $($grp.Count)" -ForegroundColor $ColorInfo
    }
}
Write-Host ""

# 3. Buscar actualizaciones de drivers
Write-Host "[+] Buscando controladores desactualizados en Windows Update..." -ForegroundColor $ColorPrimary
Write-Host "    (Esto puede tomar un momento, consultando servidores oficiales)..." -ForegroundColor $ColorMuted
Write-Host ""

$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()

# Filtrar por controladores no instalados
try {
    $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")
    $allUpgrades = $searchResult.Updates
}
catch {
    Write-Host "[ERROR] Hubo un problema al buscar actualizaciones: $_" -ForegroundColor $ColorError
    Write-Host ""
    Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor $ColorMuted
    try { [void][Console]::ReadKey($true) } catch { Read-Host }
    exit 1
}

if ($allUpgrades.Count -eq 0) {
    Write-Host "[OK] ¡Felicidades! Todos los controladores de tu laptop estan al dia." -ForegroundColor $ColorSuccess
    Write-Host ""
    
    $viewAll = Read-Host "¿Deseas ver la lista completa de todos los dispositivos de hardware detectados? (S/N)"
    if ($viewAll.Trim().ToUpper() -eq "S") {
        Write-Host ""
        Write-Host ("{0,-60} {1,-20} {2}" -f "Nombre del Dispositivo", "Categoria", "Estado") -ForegroundColor $ColorPrimary
        Write-Host ("{0,-60} {1,-20} {2}" -f "----------------------", "---------", "------") -ForegroundColor $ColorMuted
        foreach ($dev in $pnpDevices | Sort-Object FriendlyName) {
            $displayName = $dev.FriendlyName
            if ($displayName.Length -gt 57) { $displayName = $displayName.Substring(0, 54) + "..." }
            Write-Host ("{0,-60} {1,-20} " -f $displayName, $dev.Class) -NoNewline
            Write-Host $dev.Status -ForegroundColor $ColorSuccess
        }
    }
    
    Write-Host ""
    Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor $ColorMuted
    try { [void][Console]::ReadKey($true) } catch { Read-Host }
    exit 0
}

# Listar drivers desactualizados
Write-Host "Se encontraron $($allUpgrades.Count) actualizaciones de controladores disponibles:" -ForegroundColor $ColorWarning
Write-Host ""
Write-Host ("{0,-65} {1,-15} {2}" -f "Nombre del Controlador / Actualizacion", "Tamano Max", "Origen") -ForegroundColor $ColorPrimary
Write-Host ("{0,-65} {1,-15} {2}" -f "--------------------------------------", "----------", "------") -ForegroundColor $ColorMuted

foreach ($upg in $allUpgrades) {
    $displayName = $upg.Title
    if ($displayName.Length -gt 62) { $displayName = $displayName.Substring(0, 59) + "..." }
    
    # Calcular tamano
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
Write-Host " INICIANDO FLUJO INTERACTIVO DE ACTUALIZACION DE DRIVERS" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

$autoUpdateAll = $false
$rebootRequired = $false

foreach ($upg in $allUpgrades) {
    $action = "No"
    
    if (-not $autoUpdateAll) {
        while ($true) {
            Write-Host ""
            Write-Host ">>> ¿Deseas actualizar el driver: " -NoNewline
            Write-Host $upg.Title -ForegroundColor $ColorPrimary
            Write-Host "    [S] Si  [N] No  [A] Instalar todos sin preguntar  [C] Cancelar y Salir: " -NoNewline -ForegroundColor $ColorInfo
            
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
        Write-Host "[!] Proceso de actualizacion cancelado. Saliendo..." -ForegroundColor $ColorWarning
        break
    }
    
    if ($action -eq "All") {
        $autoUpdateAll = $true
        $action = "Yes"
        Write-Host "[+] Activado modo de instalacion masiva de drivers..." -ForegroundColor $ColorWarning
    }
    
    if ($action -eq "Yes") {
        Write-Host ""
        Write-Host "[+] Descargando driver: $($upg.Title)... " -NoNewline -ForegroundColor $ColorPrimary
        
        $updateCollection = New-Object -ComObject Microsoft.Update.UpdateColl
        $updateCollection.Add($upg)
        
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updateCollection
        
        try {
            $downloadResult = $downloader.Download()
            if ($downloadResult.ResultCode -eq 2) {
                Write-Host "Completado." -ForegroundColor $ColorSuccess
                
                Write-Host "[+] Instalando driver: $($upg.Title)... " -NoNewline -ForegroundColor $ColorPrimary
                $installer = $updateSession.CreateUpdateInstaller()
                $installer.Updates = $updateCollection
                
                $installResult = $installer.Install()
                if ($installResult.ResultCode -eq 2) {
                    Write-Host "Instalado." -ForegroundColor $ColorSuccess
                    if ($installResult.RebootRequired) {
                        Write-Host "[!] ADVERTENCIA: Este driver requiere reiniciar el sistema." -ForegroundColor $ColorWarning
                        $rebootRequired = $true
                    } else {
                        Write-Host "[SUCCESS] Driver instalado con exito." -ForegroundColor $ColorSuccess
                    }
                } else {
                    Write-Host "Error en instalacion (Codigo: $($installResult.ResultCode))." -ForegroundColor $ColorError
                }
            } else {
                Write-Host "Error en descarga (Codigo: $($downloadResult.ResultCode))." -ForegroundColor $ColorError
            }
        }
        catch {
            Write-Host "Error inesperado al descargar/instalar: $_" -ForegroundColor $ColorError
        }
    }
    else {
        Write-Host "[-] Saltando driver." -ForegroundColor $ColorMuted
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host "               PROCESO COMPLETADO" -ForegroundColor $ColorPrimary
Write-Host "=========================================================" -ForegroundColor $ColorPrimary
Write-Host ""

if ($rebootRequired) {
    Write-Host "[!] IMPORTANTE: Se han instalado drivers que requieren reiniciar tu laptop." -ForegroundColor $ColorWarning
    Write-Host "¿Deseas reiniciar la computadora ahora mismo? [S] Si / [N] No: " -NoNewline -ForegroundColor $ColorInfo
    
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
        Write-Host ""
        Write-Host "[+] Reiniciando sistema en 5 segundos..." -ForegroundColor $ColorSuccess
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit
    } else {
        Write-Host ""
        Write-Host "[-] Recuerda reiniciar tu laptop manualmente lo antes posible." -ForegroundColor $ColorWarning
    }
}

Write-Host ""
Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor $ColorMuted
try { [void][Console]::ReadKey($true) } catch { Read-Host }
