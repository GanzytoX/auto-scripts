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

- **[brew_list_all.sh](mac/brew_list_all.sh)**: Lists every Homebrew formula, cask, tap, and service currently installed or configured.
- **[brew_update.sh](mac/brew_update.sh)**: Checks and upgrades Homebrew formulae/casks after confirmation; supports dry runs.
- **[check_node.sh](mac/check_node.sh)**: Checks the active Node.js release line and can safely update it through its actual manager.
- **[check_python.sh](mac/check_python.sh)**: Lists installed Python versions and can update the active minor line through its actual manager.
- **[update_pnpm.sh](mac/update_pnpm.sh)**: Checks, updates, or repairs PNPM without mixing installation methods.

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
./mac/brew_list_all.sh

# Preview or confirm Homebrew upgrades
./mac/brew_update.sh --dry-run
./mac/brew_update.sh

# Check versions without making changes
./mac/check_node.sh
./mac/check_python.sh
./mac/update_pnpm.sh --check

# Offer to update the active Node.js or Python release line
./mac/check_node.sh --update
./mac/check_python.sh --update

# Check and offer to update or repair pnpm
./mac/update_pnpm.sh
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
