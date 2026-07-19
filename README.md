# Auto Scripts

A collection of clean, interactive automation scripts to manage updates for packages, applications, and drivers across Windows and macOS.

---

## 🚀 Features

- **Cross-Platform**: Tailored automation for Windows (PowerShell) and macOS (zsh).
- **Consolidated Scan**: Searches Windows Registry, Microsoft Store, NPM, and PNPM in one go.
- **Smart Elevation**: Requests Administrator privileges _Just-In-Time_ only when an install requires them.
- **Driver Updates**: Queries the native Windows Update COM API to update outdated hardware drivers.

---

## 📂 Project Structure

### 🪟 Windows (`win/`)

- **[detect-and-update-apps.ps1](win/detect-and-update-apps.ps1)**: Scans Registry, Microsoft Store (Appx/Winget), and NPM/PNPM to execute interactive, secure application updates.
- **[detect-and-update-drivers.ps1](win/detect-and-update-drivers.ps1)**: Scans hardware devices and installs driver updates via the Windows Update API.
- **[get-global-packages.ps1](win/get-global-packages.ps1)**: Lists globally installed NPM and PNPM packages.
- **[get-node-info.ps1](win/get-node-info.ps1)**: Retrieves detailed environment stats for Node.js.
- **[update-npm.ps1](win/update-npm.ps1)**: Updates NPM globally to the latest version.
- **[update-pnpm.ps1](win/update-pnpm.ps1)**: Detects installation type (NPM/standalone/corepack) and upgrades PNPM.

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

#### Update Applications (Winget, MS Store, NPM, etc.)

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-apps.ps1
```

#### Update System Drivers

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-drivers.ps1
```

---

_Made with ❤️ by **GonzaDev** to optimize system productivity and maintenance._
