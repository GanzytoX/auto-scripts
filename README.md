<div align="center">

<pre style="display: inline-block; text-align: left;">
    ___         __          _____           _       __      
   /   |  __  _/ /_____    / ___/__________(_)___  / /______
  / /| | / / / / __/ __ \  \__ \/ ___/ ___/ / __ \/ __/ ___/
 / ___ |/ /_/ / /_/ /_/ / ___/ / /__/ /  / / /_/ / /_(__  ) 
/_/  |_|\__,_/\__/\____/ /____/\___/_/  /_/ .___/\__/____/  
                                         /_/                
</pre>

[![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://apple.com)
[![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://microsoft.com)

</div>

---

## 📂 Project Structure

### 🍎 macOS Tools (`mac/`)

| Script                                                              | Description                                                                            |
| :------------------------------------------------------------------ | :------------------------------------------------------------------------------------- |
| 📋 [get_system_info.sh](mac/get_system_info.sh)                     | Hardware, OS, battery, GPU, disk, network, and runtime audit (`--brief`, `--json`).    |
| 🍺 [list_homebrew_inventory.sh](mac/list_homebrew_inventory.sh)     | Lists all Homebrew formulae, casks, taps, and services configured.                     |
| 🧾 [list_installed_software.sh](mac/list_installed_software.sh)     | Audits macOS apps, Homebrew packages, PATH entries, executables, and package receipts. |
| 🔄 [update_homebrew_packages.sh](mac/update_homebrew_packages.sh)   | Checks and upgrades Homebrew packages with dry-run support.                            |
| 🟢 [manage_node_version.sh](mac/manage_node_version.sh)             | Inspects and safely updates Node.js via active version manager.                        |
| 🐍 [manage_python_version.sh](mac/manage_python_version.sh)         | Inspects Python installations and updates patch/minor releases.                        |
| 📦 [list_global_node_packages.sh](mac/list_global_node_packages.sh) | Audits global NPM and PNPM packages with versions and file paths.                      |
| 🧹 [clean_residual_app_data.sh](mac/clean_residual_app_data.sh)     | Detects and cleans orphaned caches, preferences, LaunchAgents, and package receipts.    |
| ⚡ [manage_pnpm.sh](mac/manage_pnpm.sh)                             | Checks, updates, installs, or repairs PNPM safely.                                     |
| 🧹 [manage_npm.sh](mac/manage_npm.sh)                               | Checks, updates, or repairs NPM isolated to its active release line.                   |

### 🪟 Windows Tools (`win/`)

| Script                                                                  | Description                                                                            |
| :---------------------------------------------------------------------- | :------------------------------------------------------------------------------------- |
| 🛒 [manage-application-updates.ps1](win/manage-application-updates.ps1) | Consolidated Winget, Microsoft Store, and NPM app update check.                        |
| 🚗 [manage-driver-updates.ps1](win/manage-driver-updates.ps1)           | Queries Windows Update COM API for outdated hardware drivers.                          |
| 🟢 [manage-node-version.ps1](win/manage-node-version.ps1)               | Reports active Node.js release and updates via detected manager or official installer. |
| 📦 [list-global-node-packages.ps1](win/list-global-node-packages.ps1)   | Lists globally installed NPM and PNPM packages cleanly.                                |
| ⚡ [manage-pnpm.ps1](win/manage-pnpm.ps1)                               | Controls PNPM installation and updates without mixed methods.                          |
| 🧹 [manage-npm.ps1](win/manage-npm.ps1)                                 | Inspects or updates NPM safely without elevation side-effects.                         |

---

## 🛠️ Setup & Requirements

### 🍎 macOS Setup

- **Shell**: Zsh (default on macOS).
- **Dependencies**: `curl`. Individual utilities utilize `brew`, `node`, `python3`, or `pnpm` if available on PATH.

```zsh
# Make scripts executable
chmod +x mac/*.sh
```

### 🪟 Windows Setup

- **PowerShell**: Windows PowerShell 5.1 or PowerShell 7+.
- **Package Managers**: `winget` for Windows application management.
- **Privileges**: Normal user privileges for audits. Elevation prompt occurs only upon explicit driver update installation.

If script execution is blocked on Windows, enable local script execution for the current user:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 🚀 Usage Guide

> 📌 **Note**: All scripts default to **Check / Audit mode**. No changes will be made to your system unless you explicitly specify update flags (`--update` / `-Update`).

### 🍎 macOS Terminal Commands

<details open>
<summary><b>System Audit & Inventory</b></summary>

```zsh
# Complete hardware & OS diagnostic report
./mac/get_system_info.sh

# Concise summary or JSON export for automation
./mac/get_system_info.sh --brief
./mac/get_system_info.sh --json

# Complete Homebrew formula, cask & service inventory
./mac/list_homebrew_inventory.sh

# List installed macOS applications and Homebrew software (interactive pause per section)
./mac/list_installed_software.sh

# Run continuously without prompting between sections
./mac/list_installed_software.sh --no-pause

# List all global npm and pnpm packages
./mac/list_global_node_packages.sh

# Audit orphaned residual files from uninstalled applications (Read-only)
./mac/clean_residual_app_data.sh

# Interactively clean orphaned caches, preferences, LaunchAgents/LaunchDaemons & package receipts
# (system-level services in /Library require sudo; you will be prompted for your password)
./mac/clean_residual_app_data.sh --clean
```

</details>

<details open>
<summary><b>Package & Runtime Updates</b></summary>

```zsh
# Dry-run Homebrew update check
./mac/update_homebrew_packages.sh --dry-run

# Interactive Homebrew upgrade
./mac/update_homebrew_packages.sh

# Check Node.js and Python status (Read-only)
./mac/manage_node_version.sh
./mac/manage_python_version.sh

# Perform Node.js or Python update via detected manager
./mac/manage_node_version.sh --update
./mac/manage_python_version.sh --update

# Check/Repair NPM or PNPM
./mac/manage_pnpm.sh --check
./mac/manage_npm.sh --check
./mac/manage_pnpm.sh
./mac/manage_npm.sh
```

</details>

---

### 🪟 Windows PowerShell Commands

<details open>
<summary><b>Read-Only System & Package Audits</b></summary>

```powershell
# Consolidated Winget & Microsoft Store inventory check
powershell -NoProfile -File .\win\manage-application-updates.ps1 -Inventory

# Query available driver updates via Windows Update COM API
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -ListDevices

# Node.js, NPM, and PNPM status audit (Read-only)
powershell -NoProfile -File .\win\manage-node-version.ps1 -Check
powershell -NoProfile -File .\win\list-global-node-packages.ps1
powershell -NoProfile -File .\win\manage-npm.ps1 -Check
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Check
```

</details>

<details open>
<summary><b>Application & Driver Updates</b></summary>

```powershell
# Update installed applications
powershell -NoProfile -File .\win\manage-application-updates.ps1 -Update

# Interactive Windows driver updates (prompts for UAC elevation)
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -Update

# Update Node.js, NPM, or PNPM
powershell -NoProfile -File .\win\manage-node-version.ps1 -Update
powershell -NoProfile -File .\win\manage-npm.ps1 -Update
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Update

# Driver update with opt-in automatic system reboot
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -Update -Restart -Yes

# Explicit PNPM installation by standalone installer, npm, or corepack
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Install -InstallMethod Standalone
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Install -InstallMethod Npm
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Install -InstallMethod Corepack
```

</details>

> 💡 **Tip**: Use `-Yes` or `--yes` only in automated environments where non-interactive execution is intended.

---

<div align="center">

Made with ❤️ by **[GonzaDev](https://github.com/GanzytoX)**

</div>
