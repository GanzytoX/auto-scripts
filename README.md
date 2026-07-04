# Script Updater and Manager

This repository contains a set of tools and scripts designed to automate the detection and update of applications, global packages, and drivers on Windows and macOS.

## Project Structure

- **`win/`**: Scripts optimized for Windows operating systems.
  - **[detect-and-update-apps.ps1](win/detect-and-update-apps.ps1)**: Performs a consolidated scan of the Windows Registry (HKLM/HKCU, 32-bit and 64-bit), Microsoft Store applications (Appx/Winget), and global development environments (NPM/PNPM). It carries out interactive and secure updates using individual _Just-In-Time_ administrator elevation.
  - **[detect-and-update-drivers.ps1](win/detect-and-update-drivers.ps1)**: Scans your computer's hardware devices and queries official driver updates through the Windows Update COM API. It allows interactive installation and detects if a system restart is required.
  - **[get-global-packages.ps1](win/get-global-packages.ps1)**: Helper script to list global packages installed on the system.
  - **[get-node-info.ps1](win/get-node-info.ps1)**: Helper script to retrieve local Node.js environment information.
  - **[update-npm.ps1](win/update-npm.ps1)**: Helper script to update NPM to the latest global version.
  - **[update-pnpm.ps1](win/update-pnpm.ps1)**: Helper script to update PNPM to the latest global version.

- **`mac/`**: Scripts optimized for macOS automation.
  - **[brew_update.sh](mac/brew_update.sh)**: Helper script to update Homebrew repositories, upgrade outdated formulae and casks, and clean up temporary files.
  - **[check_node.sh](mac/check_node.sh)**: Script to check Node.js status, retrieve recent major release lines, and update/install Node.js.
  - **[update_pnpm.sh](mac/update_pnpm.sh)**: Helper script to check and update PNPM to the latest version.

## Requirements and Configuration on Windows

To execute PowerShell scripts, you must allow the execution of local scripts in your terminal. Open PowerShell and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Usage

### Updating Applications (Winget, MS Store, NPM, etc.)

Run the script in your normal user terminal. If an installation requires administrator privileges, the script will elevate individually in a temporary pop-up window:

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-apps.ps1
```

### Updating Drivers (Windows Only)

To search for and install official hardware driver updates for your computer:

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-drivers.ps1
```

---

Created with ❤️ to optimize productivity and system maintenance.
