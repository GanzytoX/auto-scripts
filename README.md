# Actualizador y Gestor de Scripts

Este repositorio contiene un conjunto de herramientas y scripts en PowerShell diseñados para automatizar la detección y actualización de aplicaciones, paquetes globales y controladores (drivers) en Windows.

## Estructura del Proyecto

* **`win/`**: Scripts optimizados para sistemas operativos Windows.
  * **[detect-and-update-apps.ps1](win/detect-and-update-apps.ps1)**: Escanea de forma consolidada el Registro de Windows (HKLM/HKCU, 32 y 64 bits), aplicaciones de la Microsoft Store (Appx/Winget) y entornos de desarrollo globales (NPM/PNPM). Realiza actualizaciones interactivas y seguras usando elevación de administrador *Just-In-Time* individual.
  * **[detect-and-update-drivers.ps1](win/detect-and-update-drivers.ps1)**: Escanea los dispositivos de hardware de tu equipo y consulta actualizaciones oficiales de controladores mediante la API COM de Windows Update. Permite instalarlos de forma interactiva y detecta si se requiere reiniciar la laptop.
  * **[get-global-packages.ps1](win/get-global-packages.ps1)**: Script auxiliar para listar paquetes globales instalados en el sistema.
  * **[get-node-info.ps1](win/get-node-info.ps1)**: Script auxiliar para obtener información del entorno Node.js local.
  * **[update-npm.ps1](win/update-npm.ps1)**: Script auxiliar para actualizar NPM a su última versión global.
  * **[update-pnpm.ps1](win/update-pnpm.ps1)**: Script auxiliar para actualizar PNPM a su última versión global.

* **`mac/`**: Reservado para futuros scripts de automatización en macOS (por ejemplo, usando Homebrew).

## Requisitos y Configuración en Windows

Para ejecutar los scripts de PowerShell, debes permitir la ejecución de scripts locales en tu terminal. Abre PowerShell y ejecuta:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Modo de Uso

### Actualización de Aplicaciones (Winget, MS Store, NPM, etc.)
Ejecuta el script en tu terminal de usuario normal. Si alguna instalación requiere privilegios de administrador, el script la elevará de forma individual en una ventana emergente temporal:

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-apps.ps1
```

### Actualización de Controladores (Drivers)
Para buscar e instalar actualizaciones oficiales de drivers de hardware de tu laptop:

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-drivers.ps1
```

---
Creado con ❤️ para optimizar la productividad y el mantenimiento del sistema.
