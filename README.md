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

## 🛠️ Requirements & Setup

### Windows

- Windows 10/11 with Windows PowerShell 5.1 or PowerShell 7.
- Winget for application inventory and application updates.
- Administrator privileges only when installing driver updates.
- Node.js, npm, pnpm, Corepack, fnm, nvm-windows, or Volta only for the corresponding Node.js management features.

If local PowerShell scripts are blocked, enable the policy for your user account:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

The scripts do not require Administrator PowerShell to perform checks. `manage-driver-updates.ps1` requests elevation only after you explicitly request an installation.

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

All Windows management scripts are read-only by default. Use `-Update` to request changes, and add `-Yes` only for deliberate non-interactive runs.

#### Read-only checks

```powershell
powershell -NoProfile -File .\win\manage-application-updates.ps1 -Inventory
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -ListDevices
powershell -NoProfile -File .\win\manage-node-version.ps1
powershell -NoProfile -File .\win\list-global-node-packages.ps1
powershell -NoProfile -File .\win\manage-npm.ps1
powershell -NoProfile -File .\win\manage-pnpm.ps1
```

#### Apply updates

```powershell
powershell -NoProfile -File .\win\manage-application-updates.ps1 -Update
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -Update
powershell -NoProfile -File .\win\manage-node-version.ps1 -Update
powershell -NoProfile -File .\win\manage-npm.ps1 -Update
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Update
```

#### Restart after driver updates

```powershell
powershell -NoProfile -File .\win\manage-driver-updates.ps1 -Update -Restart -Yes
```

#### Install pnpm explicitly

```powershell
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Install -InstallMethod Standalone
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Install -InstallMethod Npm
powershell -NoProfile -File .\win\manage-pnpm.ps1 -Install -InstallMethod Corepack
```

`-Restart` is always opt-in. PNPM installation requires `-Install` and an explicit `-InstallMethod`; it never guesses a new installation method.

---

_Made with ❤️ by **GonzaDev** to optimize system productivity and maintenance._
