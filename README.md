# Auto Scripts

A collection of clean, interactive automation scripts to manage updates for packages, applications, and drivers across Windows and macOS.

---

## 🚀 Features

- **Cross-Platform**: Tailored automation for Windows (PowerShell) and macOS (zsh).
- **Consolidated Scan**: Checks Winget, Microsoft Store, NPM, and PNPM without duplicating installed applications.
- **Scoped Elevation**: Requests Administrator privileges only when Windows driver installation requires them.
- **Driver Updates**: Queries the native Windows Update COM API to update outdated hardware drivers.

---

## 📂 Project Structure

### 🪟 Windows (`win/`)

- **[manage-application-updates.ps1](win/manage-application-updates.ps1)**: Checks Winget, Microsoft Store, and global NPM updates; installs only when requested.
- **[manage-driver-updates.ps1](win/manage-driver-updates.ps1)**: Checks Windows Update for drivers and optionally installs selected updates with scoped elevation.
- **[list-global-node-packages.ps1](win/list-global-node-packages.ps1)**: Lists globally installed NPM and PNPM packages.
- **[manage-node-version.ps1](win/manage-node-version.ps1)**: Reports the active Node.js environment and optionally updates its current major line through the detected manager.
- **[manage-npm.ps1](win/manage-npm.ps1)**: Checks or updates NPM to the latest stable version.
- **[manage-pnpm.ps1](win/manage-pnpm.ps1)**: Checks, updates, installs, or repairs PNPM without mixing installation methods.

### 🍎 macOS (`mac/`)

- **[list_homebrew_inventory.sh](mac/list_homebrew_inventory.sh)**: Lists every Homebrew formula, cask, tap, and service currently installed or configured.
- **[update_homebrew_packages.sh](mac/update_homebrew_packages.sh)**: Checks and upgrades Homebrew formulae/casks after confirmation; supports dry runs.
- **[manage_node_version.sh](mac/manage_node_version.sh)**: Checks the active Node.js release line and can safely update it through its actual manager.
- **[manage_python_version.sh](mac/manage_python_version.sh)**: Lists installed Python versions and can update the active minor line through its actual manager.
- **[list_global_node_packages.sh](mac/list_global_node_packages.sh)**: Lists globally installed npm and pnpm packages with their versions and installation paths.
- **[manage_pnpm.sh](mac/manage_pnpm.sh)**: Checks, updates, or repairs PNPM without mixing installation methods.

---

## 🛠️ Requirements & Setup (Windows)

To run PowerShell scripts on Windows, execution policies must allow local scripts. Open PowerShell and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 💻 Usage

### macOS

The macOS scripts require zsh and curl. Individual operations may also require Homebrew, Node.js, Python, or pnpm, depending on the script.

```zsh
# Read-only inventory
./mac/list_homebrew_inventory.sh

# Preview or confirm Homebrew upgrades
./mac/update_homebrew_packages.sh --dry-run
./mac/update_homebrew_packages.sh

# Check versions without making changes
./mac/manage_node_version.sh
./mac/manage_python_version.sh
./mac/manage_pnpm.sh --check

# List global npm and pnpm packages
./mac/list_global_node_packages.sh

# Offer to update the active Node.js or Python release line
./mac/manage_node_version.sh --update
./mac/manage_python_version.sh --update

# Check and offer to update or repair pnpm
./mac/manage_pnpm.sh
```

Use `--yes` only when an update has already been intentionally requested and non-interactive confirmation is appropriate. Node.js and Python never update in their default check mode. The pnpm updater never falls back to a different package manager, and it does not invoke `sudo`.

Every macOS script supports `--help` for its complete options.

### Windows

#### Check installed applications and available updates

```powershell
powershell -NoProfile -File .\win\manage-application-updates.ps1 -Inventory
```

#### Install application updates

```powershell
powershell -NoProfile -File .\win\manage-application-updates.ps1 -Update
```

#### Check or install driver updates

```powershell
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -ListDevices
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -Update
```

#### Inspect Node.js and global packages

```powershell
powershell -NoProfile -File .\win\manage-node-version.ps1
powershell -NoProfile -File .\win\list-global-node-packages.ps1
```

#### Update Node.js package managers

```powershell
powershell -NoProfile -File .\win\manage-npm.ps1 -Update
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Update
```

Windows management scripts are read-only by default. `-Update` explicitly enables changes, while `-Yes` confirms an already-requested operation non-interactively. Driver restarts require the additional `-Restart` switch. PNPM installation requires `-Install` and supports `-InstallMethod Standalone`, `Npm`, or `Corepack`.

---

_Made with ❤️ by **GonzaDev** to optimize system productivity and maintenance._
