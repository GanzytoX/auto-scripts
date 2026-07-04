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

- **[brew_update.sh](mac/brew_update.sh)**: Updates Homebrew formulae/casks and performs cleanup.
- **[check_node.sh](mac/check_node.sh)**: Checks current Node.js version and recommends updates via detected managers (fnm, nvm, brew, pnpm).
- **[update_pnpm.sh](mac/update_pnpm.sh)**: Upgrades PNPM using the detected runtime manager.

---

## 🛠️ Requirements & Setup (Windows)

To run PowerShell scripts on Windows, execution policies must allow local scripts. Open PowerShell and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 💻 Usage

### Update Applications (Winget, MS Store, NPM, etc.)

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-apps.ps1
```

### Update System Drivers

```powershell
powershell -ExecutionPolicy Bypass -File .\win\detect-and-update-drivers.ps1
```

---

_Made with ❤️ by **GonzaDev** to optimize system productivity and maintenance._
